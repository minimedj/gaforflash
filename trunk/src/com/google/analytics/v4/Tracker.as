﻿/*
 * Copyright 2008 Adobe Systems Inc., 2008 Google Inc.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *   http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * 
 * Contributor(s):
 *   Zwetan Kjukov <zwetan@gmail.com>.
 */

package com.google.analytics.v4
{
    import com.google.analytics.campaign.CampaignInfo;
    import com.google.analytics.campaign.CampaignManager;
    import com.google.analytics.core.BrowserInfo;
    import com.google.analytics.core.Buffer;
    import com.google.analytics.core.DocumentInfo;
    import com.google.analytics.core.DomainNameMode;
    import com.google.analytics.core.EventInfo;
    import com.google.analytics.core.EventTracker;
    import com.google.analytics.core.GIFRequest;
    import com.google.analytics.core.IdleTimer;
    import com.google.analytics.core.ServerOperationMode;
    import com.google.analytics.core.Utils;
    import com.google.analytics.data.X10;
    import com.google.analytics.debug.DebugConfiguration;
    import com.google.analytics.debug.VisualDebugMode;
    import com.google.analytics.external.AdSenseGlobals;
    import com.google.analytics.utils.Environment;
    import com.google.analytics.utils.Protocols;
    import com.google.analytics.utils.URL;
    import com.google.analytics.utils.Variables;
    
    import flash.display.DisplayObject;
    
    
    
    /**
     * The Tracker class.
     */
    public class Tracker implements GoogleAnalyticsAPI
    {
        /* DON'T CHANGE THE ORDER OF THE VARS */
        
        //params
        private var _account:String;
        private var _domainHash:Number;
        private var _formatedReferrer:String;
        private var _timeStamp:Number;
        private var _hasInitData:Boolean          = false;
        private var _isNewVisitor:Boolean         = false;
        private var _noSessionInformation:Boolean = false;
        
        //factory
        private var _config:Configuration;
        private var _debug:DebugConfiguration;
        private var _info:Environment;
        private var _buffer:Buffer;
        private var _gifRequest:GIFRequest;
        private var _adSense:AdSenseGlobals;
        private var _display:DisplayObject;
        
        //gif requests
        private var _browserInfo:BrowserInfo;
        private var _campaignInfo:CampaignInfo;
        
        //other
        private const EVENT_TRACKER_PROJECT_ID:int          = 5;
        private const EVENT_TRACKER_OBJECT_NAME_KEY_NUM:int = 1;
        private const EVENT_TRACKER_TYPE_KEY_NUM:int        = 2;
        private const EVENT_TRACKER_LABEL_KEY_NUM:int       = 3;
        private const EVENT_TRACKER_VALUE_VALUE_NUM:int     = 1;
        private var _campaign:CampaignManager;
        private var _eventTracker:X10;
        private var _x10Module:X10;
        private var _idleTimer:IdleTimer;
        
        /** 
         * Creates a new Tracker instance.
         * @param account Urchin Account to record metrics in.
         * @param info The LocalInfo reference of this tracker.
         * @param buffer The Buffer reference of this tracker.
         * @param gifRequest The GifRequest of this tracker.
         * @param adSense The optional adsense global object.
         * @param layout The optional Layout object.
         */
        public function Tracker( account:String,
                                 config:Configuration, debug:DebugConfiguration,
                                 info:Environment, buffer:Buffer, gifRequest:GIFRequest, adSense:AdSenseGlobals, display:DisplayObject )
        {
            _account    = account;
            
            _config     = config;
            _debug      = debug;
            _info       = info;
            _buffer     = buffer;
            _gifRequest = gifRequest;
            _adSense    = adSense;
            _display    = display;
            
            if( !Utils.validateAccount( account ) )
            {
                var msg:String = "Account \"" + account + "\" is not valid." ;
                _debug.warning( msg );
                throw new Error( msg );
            }
            
            //_initData();
        }
        
        private function _initData():void
        {
            // initialize initial data
            if( !_hasInitData )
            {
            	if (_buffer == null) 
            	{
            		_buffer = new Buffer( _config, _debug, false );
             	}
                
                if (_gifRequest == null)
                {
                	_gifRequest = new GIFRequest( _config, _debug, _buffer, _info );           
                }	
                
                _idleTimer  = new IdleTimer( _config, _debug, _display, _buffer );
                
            	   
                //find domain name
                _updateDomainName();
                
                // get domain hash
                _domainHash = _getDomainHash();
                
                //define the timestamp for start of the session
                _timeStamp  = Math.round((new Date()).getTime() / 1000);
                
                if( _debug.verbose )
                {
                    var data0:String = "";
                        data0 += "_initData 0";
                        data0 += "\ndomain name: " + _config.domainName;
                        data0 += "\ndomain hash: " + _domainHash;
                        data0 += "\ntimestamp:   " + _timeStamp + " ("+new Date(_timeStamp*1000)+")";
                    _debug.info( data0, VisualDebugMode.geek );
                }
            }
            
            if( _doTracking() )
            {
                // initializes cookies each time for page tracking, event tracking, X10,
                // transactions, custom variables
                _handleCookie();
            }
            
            //initialize tracking campaign information. handleCookie_() needs have been
            //called before campaign information can be parsed.
            if( !_hasInitData )
            {
                // no need if page is a google property
                if( _doTracking() )
                {
                    // format referrer
                    _formatedReferrer = _formatReferrer();
                    
                    // cache browser info
                    _browserInfo = new BrowserInfo( _config, _info );
                    _debug.info( "browserInfo: " + _browserInfo.toURLString(), VisualDebugMode.advanced );
                    
                    // cache campaign info
                    if( _config.campaignTracking )
                    {
                        _campaign = new CampaignManager( _config, _debug, _buffer,
                                                         _domainHash, _formatedReferrer, _timeStamp );
                        
                        _campaignInfo = _campaign.getCampaignInformation( _info.locationSearch, _noSessionInformation );
                        _debug.info( "campaignInfo: " + _campaignInfo.toURLString(), VisualDebugMode.advanced );
                    }
                }
                
                // Initialize X10 module.
                _x10Module = new X10();
                
                // Initialize event tracker module
                _eventTracker = new X10();
                
                _hasInitData = true;
            }
            
            // Initialize site overlay
            if( _config.hasSiteOverlay )
            {
                //init GASO
                _debug.warning( "Site Overlay is not supported" );
            }
            
            if( _debug.verbose )
            {
                var data:String = "";
                    data += "_initData (misc)";
                    data += "\nflash version: " + _info.flashVersion.toString(4);
                    data += "\nprotocol: " + _info.protocol;
                    data += "\ndefault domain name (auto): \"" + _info.domainName +"\"";
                    data += "\nlanguage: " + _info.language;
                    data += "\ndomain hash: " + _getDomainHash();
                    data += "\nuser-agent: " + _info.userAgent;
                _debug.info( data, VisualDebugMode.geek );
            }
        }
        
        /**
         * Handles / formats GATC cookie values.  If linker functionalities are
         * enabled, then GATC cookies parsed from linker request takes precedences
         * over stored cookies.  Also updates the __utma, __utmb, and __utmc values
         * appropriately.
         *
         * @private
         */
        private function _handleCookie():void
        {
        	  	
            //Linker functionalities are enabled.
            if( _config.allowLinker )
            {
                //not supported for now
                /* TODO:
                   use JavascriptProxy to grab the query string when the application start
                   and then parse the QS here if utma/utmb/etc. found
                */
            }
            
            
//            //Has linked cookie value.
//            if( _buffer.hasUTMA() && !_buffer.utma.isEmpty() )
//            {
//                //Linked value only have __utma.  Either __utmb, or __utmc is missing.
//                if( _buffer.utmb.isEmpty() || _buffer.utmc.isEmpty() )
//                {
//                    //We take passed in __utma value, and we update it.
//                    _buffer.updateUTMA( _timeStamp );
//                    
//                    // Indicate that there is no session information.
//                    _noSessionInformation = true;
//                }
//                /* There is session information.  We are going to extract the domainHash,
//                  just in case it doesn't agree, and we override the passed in domainHash.
//                */
//                else
//                {
//                    _domainHash = _buffer.utmb.domainHash;
//                }
//                
//                if( config.debug && config.debugVerbose )
//                {
//                    _showInfo( "linked " + _buffer.utma.toString() );
//                }
//            }
//            //Does not have linked cookie value.
//            else
//            {
                //We already have __utma value stored in document cookie.
                if( _buffer.hasUTMA() && !_buffer.utma.isEmpty() )
                {
                    /* Either __utmb, __utmc, or both are missing from document cookie.  We
                       take the existing __utma value, and update with new session
                       information.  And then we indicate that there is no session information
                       available.
                    */
                    if( !_buffer.hasUTMB() || !_buffer.hasUTMC() )
                    {
                        _buffer.updateUTMA( _timeStamp );
                        _noSessionInformation = true;
                    }
                    
                    if( _debug.verbose )
                    {
                        _debug.info( "from cookie " + _buffer.utma.toString(), VisualDebugMode.geek );
                    }
                    
                }
                /* We don't have __utma value already stored in document cookie.  We are not
                   going to construct a new __utma value.  Also indicate that there is no
                   session information stored in cookie.
                */
                else
                {
                    _debug.info( "create a new utma", VisualDebugMode.advanced );
                    _buffer.utma.domainHash   = _domainHash;
                    _buffer.utma.sessionId    = _getUniqueSessionId();
                    _buffer.utma.firstTime    = _timeStamp;
                    _buffer.utma.lastTime     = _timeStamp;
                    _buffer.utma.currentTime  = _timeStamp;
                    _buffer.utma.sessionCount = 1;
                    
                    if( _debug.verbose )
                    {
                        _debug.info( _buffer.utma.toString(), VisualDebugMode.geek );
                    }
                    
                    _noSessionInformation = true;
                    _isNewVisitor         = true;
                }
//            }
            
            /* Respect the AdSense DOM globals, but only if they match the
               current domainHash.
               There are 2 scenarios when we have AS globals:
                - AS globals + new visitor:
                    Copy all info (vid, sid) from globals.
                - AS globals + returning visitor:
                    Copy only sid from globals.
            */
            if( (_adSense.gaGlobal) && (_adSense.dh == String(_domainHash)) )
            {
                /* Over-write current session time with sid from AdSense globals.
                   We always copy this to ensure that the timestamp is consistent
                   between GA and AS.
                */
                if( _adSense.sid )
                {
                    _buffer.utma.currentTime = Number( _adSense.sid );
                    
                    if( _debug.verbose )
                        {
                            var data0:String = "";
                                data0 += "AdSense sid found\n";
                                data0 += "Override currentTime("+_buffer.utma.currentTime+") from AdSense sid("+Number(_adSense.sid)+")";
                            
                            _debug.info( data0, VisualDebugMode.geek );
                        }
                }
                
                //For new visitors, copy over all the info from the AdSense globals.
                if( _isNewVisitor )
                {
                    /* Over-write the last session timestamp with the current session
                       timestamp if this is a new visitor.
                    */
                    if( _adSense.sid )
                    {
                        _buffer.utma.lastTime = Number( _adSense.sid );
                        
                        if( _debug.verbose )
                        {
                            var data1:String = "";
                                data1 += "AdSense sid found (new visitor)\n";
                                data1 += "Override lastTime("+_buffer.utma.lastTime+") from AdSense sid("+Number(_adSense.sid)+")";
                            
                            _debug.info( data1, VisualDebugMode.geek );
                        }
                    }
                    
                    /* Over-write visitor id, and first session timestamp with visitor id
                       from DOM.
                    */
                    if( _adSense.vid )
                    {
                        var vid:Array = _adSense.vid.split( "." );
                        _buffer.utma.sessionId = Number( vid[0] );
                        _buffer.utma.firstTime = Number( vid[1] );
                        
                        if( _debug.verbose )
                        {
                            var data2:String = "";
                                data2 += "AdSense vid found (new visitor)\n";
                                data2 += "Override sessionId("+_buffer.utma.sessionId+") from AdSense vid("+Number( vid[0] )+")\n";
                                data2 += "Override firstTime("+_buffer.utma.firstTime+") from AdSense vid("+Number( vid[1] )+")";
                            
                            _debug.info( data2, VisualDebugMode.geek );
                        }
                    }
                    
                    if( _debug.verbose )
                    {
                        _debug.info( "AdSense modified : " + _buffer.utma.toString(), VisualDebugMode.geek );
                    }
                }
                
            }
                
            /* Sets the common __utmb, __utmc values.
               note: we are resetting the count for every new session.
            */
            _buffer.utmb.domainHash = _domainHash;
            
            if( isNaN( _buffer.utmb.trackCount ) )
            {
                _buffer.utmb.trackCount = 0;
            }
            
            if( isNaN( _buffer.utmb.token ) )
            {
                _buffer.utmb.token = _config.tokenCliff;
            }
            
            if( isNaN( _buffer.utmb.lastTime ) )
            {
                _buffer.utmb.lastTime = _buffer.utma.currentTime;
            }
            
            _buffer.utmc.domainHash = _domainHash;
            
            if( _debug.verbose )
            {
                _debug.info( _buffer.utmb.toString(), VisualDebugMode.advanced );
                _debug.info( _buffer.utmc.toString(), VisualDebugMode.advanced );
            }
            
        }
        
        /**
         * Returns true if and only if the cookie domain is NOT a google search page.
         * @return {Boolean} Return true if and only if the cookie domain is not a google search page.
         * @private
         */
        private function _isNotGoogleSearch():Boolean
        {
            var domainName:String = _config.domainName;
            
            var g0:Boolean = domainName.indexOf( "www.google." ) < 0;
            var g1:Boolean = domainName.indexOf( ".google."    ) < 0;
            var g2:Boolean = domainName.indexOf( "google."     ) < 0;
            
            /* note:
               google.org is not a google search page.
            */
            var g4:Boolean = domainName.indexOf( "google.org"  ) > -1;
            
            return (g0 || g1 || g2) || (_config.cookiePath != "/") || g4;
        }
        
        /**
         * Returns predicate indicating whether we should track this page.  Only track
         * page if it's not residing on local machine (file protocol), and the page is
         * not sitting on the google domain.
         *
         * @return {Boolean} True if and only if the page is not sitting no local
         *     machine, and it's not sitting on a google domain.
         */
        private function _doTracking():Boolean
        {
            if( (_info.protocol != Protocols.file) &&
                (_info.protocol != Protocols.none) &&
                _isNotGoogleSearch() )
                {
                    return true;
                }
            
            if( _config.allowLocalTracking )
            {
                return true;
            }
            
            /* TODO:
               add logic for AIR and other running local exe
               by default a SWF running ina projector or in AIR
               will have a file:// protocol
            */
            return false;
        }
        
        /**
         * Resolves domain name from document object if domain name is set to "auto".
         * @private
         */
        private function _updateDomainName():void
        {
            if( _config.domain.mode == DomainNameMode.auto )
            {
                var domainName:String = _info.domainName;
                
                if( domainName.substring(0,4) == "www." )
                {
                    domainName = domainName.substring(4);
                }
                
                _config.domain.name = domainName;
            }
            
            _config.domainName = _config.domain.name.toLowerCase();
            _debug.info( "domain name: " + _config.domainName, VisualDebugMode.advanced );
        }
        
        /**
         * Formats document referrer.
         */
        private function _formatReferrer():String
        {
            var referrer:String = _info.referrer;
            
            //if there is no referrer
            if( (referrer == "") || (referrer == "localhost") )
            {
                referrer = "-";
            }
            //if there is a referrer
            else
            {
                var domainName:String = _info.domainName;
                var ref:URL = new URL( referrer );
                var dom:URL = new URL( "http://" + domainName );
                
                if( ref.hostName == domainName )
                {
                    return "-";
                }
                
                /* If referrer is in the sub-domain of document,
                   then formatted referrer is set to "0".
                */
                if( dom.domain == ref.domain )
                {
                    //no self-referral
                    if( dom.subDomain != ref.subDomain )
                    {
                        referrer = "0";
                    }
                }
                
                //no referrer if referrer is enclosed in square-brackets
                if( (referrer.charAt(0) == "[") && (referrer.charAt(referrer.length-1)) )
                {
                    referrer = "-";
                }
            }
            
            _debug.info( "formated referrer: " + referrer, VisualDebugMode.advanced );
            return referrer;
        }
        
        /**
         * This method generates a hashed value from the user-specific navigator,
         * window and document properties.
         *
         * @private
         * @return {Number} hash value of the user-specific properties.
         */
        private function _generateUserDataHash():Number
        {
            var hash:String = "";
                hash       += _info.appName;
                hash       += _info.appVersion;
                hash       += _info.language;
                hash       += _info.platform;
                hash       += _info.userAgent.toString();
                hash       += _info.screenWidth+"x"+_info.screenHeight+_info.screenColorDepth;
                hash       += _info.referrer;
                
            return Utils.generateHash(hash);
        }
        
        /**
         * Generates the unique session id from the current user specific properties
         * and a random number.
         *
         * @private
         * @return {Number} a 32 bit unique number.
         */
        private function _getUniqueSessionId():Number
        {
            var sessionID:Number = (Utils.generate32bitRandom() ^ _generateUserDataHash()) * 0x7fffffff;
            _debug.info( "Session ID: " + sessionID, VisualDebugMode.geek );
            return sessionID;
        }
        
        /**
         * If the domain name is initialized to "auto", then automatically trying to
         * resolve cookie domain name from document object.  The resolved domain name
         * will be stored in the domain name instance variable, which could be
         * accessed by the set/getDomainName methods.  If domain hashing is turn on,
         * then the hash of the domain name is also returned.  Else, hash value is
         * always 1.
         *
         * @private
         * @return {Number} If the domain name is empty (undefined, empty string, or
         *     "none"), then return 1 as the hash of domain name.  If hashing is
         *     turned off , then return 1 as the hash value as well.  If there is a
         *     domain name, and domain hashing is turned on, then return the hash of
         *     the domain name.
         */
        private function _getDomainHash():Number
        {
            if( !_config.domainName || (_config.domainName == "") ||
                _config.domain.mode == DomainNameMode.none )
            {
                _config.domainName = "";
                return 1;
            }
            
            _updateDomainName();
            
            if( _config.allowDomainHash )
            {
                return Utils.generateHash( _config.domainName );
            }
            else
            {
                return 1;
            }
        }
        
        /**
        * Returns the session ID from __utma.
        */
        private function _visitCode():Number
        {
            if( _debug.verbose )
            {
                _debug.info( "visitCode: " + _buffer.utma.sessionId, VisualDebugMode.geek );
            }
            return _buffer.utma.sessionId;
        }
        
        /**
         * This method returns true to indicate GATC will take this sample.  Or false
         * to indicate GATC will skip this sample.  Sampling decision is a function of
         * sample rate (a percentage) and the session ID.
         *
         * @param {String} sessionId Used to decide whether we should sample this
         *     session.
         *
         * @private
         * @return <code class="prettyprint">true</code> to indicate we should record this hit. <code class="prettyprint">false</code> to indicate we should skip this hit.
         */
        private function _takeSample():Boolean
        {
            /* note:
               be carefull here
               GA.js sampleRate returns 0 to 100
               with
               (selfRef._visitCode() % 10000) < (config.sampleRate_ * 100);
               
               our config.sampleRate returns 0 to 1 (0.1=10%, etc.)
               so we use
               (_visitCode() % 10000) < (config.sampleRate * 10000);
               
               some explanations:
               visitCode() returns the utma sessionID which will always be a unique 32bit number
               a 32-bit number will always distribute in the same range when %(modulo) 10000
               (from ~1000 to ~6000)
               
               so as each user get a unique 32-bit number per session
               the sampleRate allow to take a percentage of those unique users
               
               so here, the thing to understand is that the sampleRate apply
               to all the users that visit the web site, it's not the sampleRate
               of data taken from only 1 user.
            */
            if( _debug.verbose )
            {
                _debug.info( "takeSample: (" +(_visitCode() % 10000)+ ") < (" +(_config.sampleRate * 10000)+ ")", VisualDebugMode.geek );
            }
            return (_visitCode() % 10000) < (_config.sampleRate * 10000);
        }
        
        
        // ----------------------------------------
        // Basic Configuration
        // Methods that you use for customizing all aspects of Google Analytics reporting.
                
        
        /**
         * Returns the Google Analytics tracking ID for this tracker object.
         * If you are tracking pages on your website in multiple accounts,
         * you can use this method to determine the account that is associated
         * with a particular tracker object.
         * @return the Account ID this tracker object is instantiated with.
         */
        public function getAccount():String
        {
            _debug.info( "getAccount()" );
            return _account;
        }
        
        /**
         * Returns the GATC version number.
         * @return GATC version number.
         */       
        public function getVersion():String
        {
            _debug.info( "getVersion()" );
            return _config.version;
        }
        
        /**
         * Reset the current session clearing the utmb and utmc cookies.
         */
        public function resetSession():void
        {
        	_initData();
            _debug.info( "resetSession()" );
            _buffer.resetCurrentSession();
        }
        
        /**
         * Sets the new sample rate. 
         * <p>If your website is particularly large and subject to heavy traffic spikes,
         * then setting the sample rate ensures un-interrupted report tracking.</p>
         * <p>Sampling in Google Analytics occurs consistently across unique visitors,
         * so there is integrity in trending and reporting even when sampling is enabled,
         * because unique visitors remain included or excluded from the sample, as set from the initiation of sampling.</p>
         * @param newRate New sample rate to set. Provide a numeric as a whole percentage, 0.1 being 10%, 1 being 100%.
         */        
        public function setSampleRate(newRate:Number):void
        {
            if( newRate < 0 )
            {
                _debug.warning( "sample rate can not be negative, ignoring value." );
            }
            else
            {
                _config.sampleRate = newRate;
            }
            
            _debug.info( "setSampleRate( " + _config.sampleRate + " )" );
        }
        
        /**
         * Sets the new session timeout in seconds.
         * By default, session timeout is set to 30 minutes (1800 seconds).
         * 
         * Session timeout is used to compute visits,
         * since a visit ends after 30 minutes of browser inactivity or upon browser exit.
         * If you want to change the definition of a "session" for your particular needs,
         * you can pass in the number of seconds to define a new value.
         * 
         * This will impact the Visits reports in every section where the number of
         * visits are calculated, and where visits are used in computing other values.
         * For example, the number of visits will increase if you shorten the session timeout,
         * and will decrease if you increase the session timeout.
         * 
         * @param newTimeout New session timeout to set in seconds.
         */        
        public function setSessionTimeout(newTimeout:int):void
        {
            _config.sessionTimeout = newTimeout;
            _debug.info( "setSessionTimeout( " + _config.sessionTimeout + " )" );
        }
        
        /**
         * Sets a user-defined value.
         * The value you supply appears as an option in the Segment pull-down for the Traffic Sources reports.
         * You can use this value to provide additional segmentation on users to your website.
         * 
         * For example, you could have a login page or a form that triggers a value based on a visitor's input,
         * such as a preference the visitor chooses, or a privacy option.
         * This variable is then updated in the cookie for that visitor.
         * 
         * @param newVal New user defined value to set.
         */
        public function setVar(newVal:String):void
        {
            if( (newVal != "") && _isNotGoogleSearch() )
            {
                _initData();
                
                _buffer.utmv.domainHash = _domainHash;
                _buffer.utmv.value      = newVal;
                
                if( _debug.verbose )
                {
                    _debug.info( _buffer.utmv.toString(), VisualDebugMode.geek );
                }
                
                _debug.info( "setVar( " + newVal + " )" );
                
                if( _takeSample() )
                {
                    var variables:Variables = new Variables();
                        variables.utmt = "var";
                        
                    _gifRequest.send( _account, variables );
                }
                
            }
            else
            {
                _debug.warning( "setVar \"" + newVal + "\" is ignored" );
            }
        }
        
        /**
         * Main logic for GATC (Google Analytic Tracker Code).
         * If linker functionalities are enabled, it attempts to extract cookie values from the URL.
         * Otherwise, it tries to extract cookie values from document.cookie.
         * It also updates or creates cookies as necessary, then writes them back to the document object.
         * Gathers all the appropriate metrics to send to the UCFE (Urchin Collector Front-end).
         * 
         * @param pageURL Optional parameter to indicate what page URL to track metrics under. When using this option, use a beginning slash (/) to indicate the page URL.
         */        
        public function trackPageview(pageURL:String=""):void
        {
            _debug.info( "trackPageview( " + pageURL + " )" );
            //Do nothing if we decided to not track this page.
            if( _doTracking() )
            {
                _initData();
                
                //ignoredOutboundHosts_ ?
                
                //track metrics (sent data to GABE)
                _trackMetrics( pageURL );
                
                _noSessionInformation = false;
            }
            else
            {
                _debug.warning( "trackPageview( " + pageURL + " ) failed" );
            }
        }
        
        /**
         * This method will gather metric data needed and construct it into a search 
         * string to be sent via a GIF request.  It is used by any tracking methods 
         * that needs browser, campaign, and document information to be sent.
         * @param pageURL This is the virtual page URL for the page view (optional).
         * @return The rendered search string with various information included.
         * @private
         */
        private function _renderMetricsSearchVariables( pageURL:String = "" ):Variables
        {
            var variables:Variables = new Variables();
                variables.URIencode = true;
                
            var docInfo:DocumentInfo = new DocumentInfo( _config, _info, _formatedReferrer, pageURL, _adSense );
            _debug.info( "docInfo: " + docInfo.toURLString(), VisualDebugMode.geek );
            
            var campvars:Variables;
            
            if( _config.campaignTracking )
            {
                campvars = _campaignInfo.toVariables();
            }
            
            var browservars:Variables = _browserInfo.toVariables();
            
            variables.join( docInfo.toVariables(),
                            browservars,
                            campvars );
            
            return variables;
        }
        
        /**
         * This method will gather all the data needed, and sent these data to GABE (Google Analytics Back-end) via GIF requests.
         * @param pageURL Page URL to assign metrics to at the back-end (optional).
         * @private
         */
        private function _trackMetrics( pageURL:String = "" ):void
        {
            if( _takeSample() )
            {
                //gif request parameters
                var searchVariables:Variables = new Variables();
                    searchVariables.URIencode = true;
                
                var x10vars:Variables;
                
                //X10
                if( _x10Module && _x10Module.hasData() )
                {
                    var eventInfo:EventInfo = new EventInfo( false, _x10Module );
                    x10vars = eventInfo.toVariables();
                }
                
                //Browser, campaign, and document information.
                var generalvars:Variables = _renderMetricsSearchVariables( pageURL );
                
                searchVariables.join( x10vars, generalvars );
                
                _gifRequest.send( _account, searchVariables );
            }
        }
        
        // ----------------------------------------
        // Campaign Tracking
        // Methods that you use for setting up and customizing campaign tracking in Google Analytics reporting.
        
        /**
        * Allows the # sign to be used as a query string delimiter in campaign tracking.
        * This option is disabled by default.
        * 
        * Typically, campaign tracking URLs are comprised of the question mark (?) separator
        * and the ampersand (&) as delimiters for the key/value pairs that make up the query.
        * By enabling this option, your campaign tracking URLs can use a pound (#) sign
        * instead of the question mark (?).
        * 
        * @param enable If this parameter is set to true, then campaign will use anchors. Else, campaign will use search strings.
        */        
        public function setAllowAnchor(enable:Boolean):void
        {
            _config.allowAnchor = enable;
            _debug.info( "setAllowAnchor( " + _config.allowAnchor + " )" );
        }
        
        /**
         * Sets the campaign ad content key.
         * The campaign content key is used to retrieve the ad content (description)
         * of your advertising campaign from your campaign URLs.
         * Use this function on the landing page defined in your campaign.
         * 
         * @param newCampContentKey New campaign content key to set.
         */        
        public function setCampContentKey(newCampContentKey:String):void
        {
            _config.campaignKey.UCCT = newCampContentKey;
            
            var msg:String = "setCampContentKey( " + _config.campaignKey.UCCT + " )";
            
            if( _debug.mode == VisualDebugMode.geek )
            {
                _debug.info( msg + " [UCCT]" );
            }
            else
            {
                _debug.info( msg );
            }
        }
        
        /**
         * Sets the campaign medium key,
         * which is used to retrieve the medium from your campaign URLs.
         * The medium appears as a segment option in the Campaigns report.
         * 
         * @param newCampMedKey Campaign medium key to set.
         */
        public function setCampMediumKey(newCampMedKey:String):void
        {
            _config.campaignKey.UCMD = newCampMedKey;
            
            var msg:String = "setCampMediumKey( " + _config.campaignKey.UCMD + " )";
            
            if( _debug.mode == VisualDebugMode.geek )
            {
                _debug.info( msg + " [UCMD]" );
            }
            else
            {
                _debug.info( msg );
            }
        }
        
        /**
         * Sets the campaign name key.
         * The campaign name key is used to retrieve the name of your advertising campaign from your campaign URLs.
         * You would use this function on any page that you want to track click-campaigns on.
         * 
         * @param newCampNameKey Campaign name key.
         */
        public function setCampNameKey(newCampNameKey:String):void
        {
            _config.campaignKey.UCCN = newCampNameKey;
            
            var msg:String = "setCampNameKey( " + _config.campaignKey.UCCN + " )";
            
            if( _debug.mode == VisualDebugMode.geek )
            {
                _debug.info( msg + " [UCCN]" );
            }
            else
            {
                _debug.info( msg );
            }
        }
        
        /**
         * Sets the campaign no-override key variable,
         * which is used to retrieve the campaign no-override value from the URL.
         * By default, this variable and its value are not set.
         * 
         * For campaign tracking and conversion measurement, this means that, by default,
         * the most recent impression is the campaign that is credited in your conversion tracking.
         * If you prefer to associate the first-most impressions to a conversion,
         * you would set this method to a specific key, and in the situation where you use custom campaign variables,
         * you would use this method to set the variable name for campaign overrides.
         * The no-override value prevents the campaign data from being over-written
         * by similarly-defined campaign URLs that the visitor might also click on.
         * 
         * @param newCampNOKey Campaign no-override key to set.
         */
        public function setCampNOKey(newCampNOKey:String):void
        {
            _config.campaignKey.UCNO = newCampNOKey;
            
            var msg:String = "setCampNOKey( " + _config.campaignKey.UCNO + " )";
            
            if( _debug.mode == VisualDebugMode.geek )
            {
                _debug.info( msg + " [UCNO]" );
            }
            else
            {
                _debug.info( msg );
            }
        }
        
        /**
         * Sets the campaign source key,
         * which is used to retrieve the campaign source from the URL.
         * "Source" appears as a segment option in the Campaigns report.
         * 
         * @param newCampSrcKey Campaign source key to set.
         */
        public function setCampSourceKey(newCampSrcKey:String):void
        {
            _config.campaignKey.UCSR = newCampSrcKey;
            
            var msg:String = "setCampSourceKey( " + _config.campaignKey.UCSR + " )";
            
            if( _debug.mode == VisualDebugMode.geek )
            {
                _debug.info( msg + " [UCSR]" );
            }
            else
            {
                _debug.info( msg );
            }
        }
        
        /**
         * Sets the campaign term key,
         * which is used to retrieve the campaign keywords from the URL.
         * 
         * @param newCampTermKey Term key to set.
         */
        public function setCampTermKey(newCampTermKey:String):void
        {
            _config.campaignKey.UCTR = newCampTermKey;
            
            var msg:String = "setCampTermKey( " + _config.campaignKey.UCTR + " )";
            
            if( _debug.mode == VisualDebugMode.geek )
            {
                _debug.info( msg + " [UCTR]" );
            }
            else
            {
                _debug.info( msg );
            }
        }
        
        /**
         * Sets the campaign tracking flag.
         * By default, campaign tracking is enabled for standard Google Analytics set up.
         * If you wish to disable campaign tracking and the associated cookies
         * that are set for campaign tracking, you can use this method.
         * 
         * @param enable True by default, which enables campaign tracking. If set to false, campaign tracking is disabled.
         */        
        public function setCampaignTrack( enable:Boolean ):void
        {
            _config.campaignTracking = enable;
            _debug.info( "setCampaignTrack( " + _config.campaignTracking + " )" );
        }
        
        /**
         * Sets the campaign tracking cookie expiration time in seconds.
         * By default, campaign tracking is set for 6 months.
         * In this way, you can determine over a 6-month period whether visitors
         * to your site convert based on a specific campaign.
         * However, your business might have a longer or shorter campaign time-frame,
         * so you can use this method to adjust the campaign tracking for that purpose.
         * 
         * @param newDefaultTimeout New default cookie expiration time to set.
         */
        public function setCookieTimeout(newDefaultTimeout:int):void
        {
            _config.conversionTimeout = newDefaultTimeout;
            _debug.info( "setCookieTimeout( " + _config.conversionTimeout + " )" );
        }
        
        // ----------------------------------------
        // Domains and Directories
        // Methods that you use for customizing how Google Analytics reporting works across domains,
        // across different hosts, or within sub-directories of a website.
        
        /**
         * Changes the paths of all GATC cookies to the newly-specified path.
         * Use this feature to track user behavior from one directory structure
         * to another on the same domain.
         * 
         * In order for this to work, the GATC tracking data must be initialized (initData() must be called).
         * 
         * @param newPath New path to store GATC cookies under.
         */
        public function cookiePathCopy(newPath:String):void
        {
            _debug.warning( "cookiePathCopy( " + newPath + " ) not implemented" );
        }
        
        /**
         * This method works in conjunction with the setDomainName() and
         * setAllowLinker() methods to enable cross-domain user tracking.
         * The link() method passes the cookies from this site to another via URL parameters (HTTP GET).
         * It also changes the document.location and redirects the user to the new URL.
         * 
         * @param targetUrl URL of target site to send cookie values to.
         * @param useHash Set to true for passing tracking code variables by using the # anchortag separator rather than the default ? query string separator. (Currently this behavior is for internal Google properties only.)
         */
        public function link(targetUrl:String, useHash:Boolean=false):void
        {
            _debug.warning( "link( " + [targetUrl,useHash].join( ", " ) + " ) not implemented" );
        }
        
        /**
         * This method works in conjunction with the setDomainName() and
         * setAllowLinker() methods to enable cross-domain user tracking.
         * The linkByPost() method passes the cookies from the referring form
         * to another site in a string appended to the action value of the form (HTTP POST).
         * This method is typically used when tracking user behavior from one site to
         * a 3rd-party shopping cart site, but can also be used to send cookie data to
         * other domains in pop-ups or in iFrames.
         * 
         * @param formObject Form object encapsulating the POST request.
         * @param useHash Set to true for passing tracking code variables by using the # anchortag separator rather than the default ? query string separator.
         */        
        public function linkByPost(formObject:Object, useHash:Boolean=false):void
        {
            _debug.warning( "linkByPost( " + [formObject,useHash].join( ", " ) + " ) not implemented" );
        }
        
        /**
         * Sets the allow domain hash flag.
         * By default, this value is set to true.
         * The domain hashing functionality in Google Analytics creates a hash value from your domain,
         * and uses this number to check cookie integrity for visitors.
         * If you have multiple sub-domains, such as example1.example.com and example2.example.com,
         * and you want to track user behavior across both of these sub-domains,
         * you would turn off domain hashing so that the cookie integrity check will not reject
         * a user cookie coming from one domain to another.
         * Additionally, you can turn this feature off to optimize per-page tracking performance.
         * 
         * @param enable If this parameter is set to true, then domain hashing is enabled. Else, domain hashing is disabled. True by default.
         */        
        public function setAllowHash(enable:Boolean):void
        {
            _config.allowDomainHash = enable;
            _debug.info( "setAllowHash( " + _config.allowDomainHash + " )" );
        }
        
        /**
         * Sets the linker functionality flag as part of enabling cross-domain user tracking.
         * By default, this method is set to false and linking is disabled.
         * See also link(), linkByPost(), and setDomainName() methods to enable cross-domain tracking.
         * 
         * @param enable If this parameter is set to true, then linker is enabled. Else, linker is disabled.
         */        
        public function setAllowLinker(enable:Boolean):void
        {
            _config.allowLinker = enable;
            _debug.info( "setAllowLinker( " + _config.allowLinker + " )" );
        }
        
        /**
         * Sets the new cookie path for your site.
         * By default, Google Analytics sets the cookie path to the root level (/).
         * In most situations, this is the appropriate option and works correctly with
         * the tracking code you install on your website, blog, or corporate web directory.
         * However, in a few cases where user access is restricted to only a sub-directory of a domain,
         * this method can resolve tracking issues by setting a sub-directory as the default path for all tracking.
         * Typically, you would use this if your data is not being tracked and you subscribed to a blog service
         * and only have access to your defined sub-directory, or if you are on a Corporate or University network
         * and only have access to your home directory.
         * In these cases, using a terminal slash is the recommended practice for defining the sub-directory.
         * 
         * @param newCookiePath New cookie path to set.
         */        
        public function setCookiePath(newCookiePath:String):void
        {
            _config.cookiePath = newCookiePath;
            _debug.info( "setCookiePath( " + _config.cookiePath + " )" );
        }
        
        /**
         * Sets the domain name for cookies.
         * There are three modes to this method: ("auto" | "none" | [domain]).
         * By default, the method is set to auto, which attempts to resolve
         * the domain name based on the location object in the DOM.
         * 
         * @param newDomainName New default domain name to set.
         */        
        public function setDomainName(newDomainName:String):void
        {
            if( newDomainName == "auto" )
            {
                _config.domain.mode = DomainNameMode.auto;
            }
            else if( newDomainName == "none" )
            {
                _config.domain.mode = DomainNameMode.none;
            }
            else
            {
                _config.domain.mode = DomainNameMode.custom;
                _config.domain.name = newDomainName;
            }
            
            _updateDomainName();
            _debug.info( "setDomainName( " + _config.domainName + " )" );
        }
        
        // ----------------------------------------
        // Ecommerce
        // Methods that you use for customizing ecommerce in Google Analytics reporting.
        
        /**
         * Adds a transaction item to the parent transaction object.
         * Use this method to track items purchased by visitors to your ecommerce site.
         * This method tracks items by SKU and performs no additional ecommerce calculations (such as quantity calculations).
         * Therefore, if the item being added is a duplicate (by SKU) of an existing item for that session,
         * then the old information is replaced with the new.
         * Additionally, it does not enforce the creation of a parent transation object,
         * but it is advised that you set this up explicitly in your transaction tracking code.
         * If no parent transaction object exists for the item, the item is attached to an empty transaction object instead.
         * 
         * @param item
         * @param sku Item's SKU code (required).
         * @param name Product name.
         * @param category Product category.
         * @param price Product price (required).
         * @param quantity Purchase quantity (required).
         */        
        public function addItem(item:String, sku:String, name:String, category:String, price:Number, quantity:int):void
        {
            _debug.warning( "addItem( " + [item,sku,name,category,price,quantity].join( ", " ) + " ) not implemented" );
        }
        
        /**
         * Creates a transaction object with the given values.
         * As with addItem(), this method handles only transaction tracking and provides no additional ecommerce functionality.
         * Therefore, if the transaction is a duplicate of an existing transaction for that session,
         * the old transaction values are over-written with the new transaction values.
         * 
         * @param orderId Internal unique order id number for this transaction.
         * @param affiliation Optional partner or store affiliation. (undefined if absent)
         * @param total Total dollar amount of the transaction.
         * @param tax Tax amount of the transaction.
         * @param shipping Shipping charge for the transaction.
         * @param city City to associate with transaction.
         * @param state State to associate with transaction.
         * @param country Country to associate with transaction.
         * @return The tranaction object that was modified.
         */        
        public function addTrans(orderId:String, affiliation:String, total:Number, tax:Number, shipping:Number, city:String, state:String, country:String):Object
        {
            _debug.warning( "addTrans( " + [orderId,affiliation,total,tax,shipping,city,state,country].join( ", " ) + " ) not implemented" );
            return null;
        }
        
        /**
         * Sends both the transaction and item data to the Google Analytics server.
         * This method should be called after trackPageview(),
         * and used in conjunction with the addItem() and addTrans() methods.
         * It should be called after items and transaction elements have been set up.
         */        
        public function trackTrans():void
        {
            _debug.warning( "trackTrans() not implemented" );
        }
        
        // ----------------------------------------
        // Event Tracking interface
        // note: not available in the public API
        
        /**
         * @private
         * Public interface for setting an X10 string key.
         *
         * @param {Number} projectId The project ID for which to set a value.
         * @param {Number} num The numeric index for which to set a value.
         * @param {String} value The value to be set into the specified indices.
         */
//        private function _setXKey( projectId:Number, num:Number, value:String ):void
//        {
//            _x10Module.setKey( projectId, num, value );
//        }
        
        /**
         * @private
         * Public Interface for getting an X10 string key.
         *
         * @param {Number} projectId The project ID for which to get a value.
         * @param {Number} num The numeric index for which to get a value.
         *
         * @return {String} The requested key, null if not found.
         */
//        private function _getXKey( projectId:Number, num:Number ):String
//        {
//            return _x10Module.getKey( projectId, num );
//        }
        
        /**
        * @private
         * Public interface for clearing all X10 string keys for a given project ID.
         *
         * @param {Number} projectId The project ID for which to clear all keys.
         */
//        private function _clearXKey( projectId:Number ):void
//        {
//            _x10Module.clearKey( projectId );
//        }
        
        /**
        * @private
         * Public interface for setting an X10 integer value.
         *
         * @param {Number} projectId The project ID for which to set a value.
         * @param {Number} num The numeric index for which to set a value.
         * @param {Number} value The value to be set into the specified indices.
         */
//        private function _setXValue( projectId:Number, num:Number, value:Number ):void
//        {
//            _x10Module.setValue( projectId, num, value );
//        }
        
        /**
         * @private
         * Public interface for getting an X10 integer value.
         *
         * @param {Number} projectId The project ID for which to get a value.
         * @param {Number} num The numeric index for which to get a value.
         *
         * @return {String} The requested value in string form, null if not found.
         */
//        private function _getXValue( projectId:Number, num:Number ):*
//        {
//            return _x10Module.getValue( projectId, num );
//        }
        
        /**
         * @private
         * Public interface for clearing all X10 integer values for a given project ID.
         *
         * @param {Number} projectId The project ID for which to clear all values.
         */
//        private function _clearXValue( projectId:Number ):void
//        {
//            _x10Module.clearValue( projectId );
//        }
        
        /**
         * Public interface for spawning new X10 objects. These are used to keep 
         * track of event-based data (as opposed to the persistent data kept on 
         * the self.X10Module_ object) that need to be stored separately.
         * @private
         * @return A new X10 object.
         */
//        private function _createXObj():X10
//        {
//            _initData();
//            return new X10();
//        }
        
        /**
         * @private
         * Public interface for sending an event. This will render all event-based
         * data along with Analytics data previously collected on pageview and send
         * the event to collectors.
         *
         * @param {_gat.GA_X10_} opt_xObj Event-based X10 data that we may want to
         *     augment to the persistent X10 data stored on the tracker object
         *     instance.
         */
        private function _sendXEvent( opt_xObj:X10 = null ):void
        {
            _initData();
            
            if( _takeSample() )
            {
                var searchVariables:Variables = new Variables();
                    searchVariables.URIencode = true;
                
                var eventInfo:EventInfo = new EventInfo( true, _x10Module, opt_xObj );
                
                var eventvars:Variables   = eventInfo.toVariables();
                var generalvars:Variables = _renderMetricsSearchVariables();
                
                searchVariables.join( eventvars, generalvars );
                
                _gifRequest.send( _account, searchVariables, false, true );
            }
        }
        
        // ----------------------------------------
        
        
        /**
         * Creates an event tracking object with the specified name.
         * Call this method when you want to create a new web page object
         * to track in the Event Tracking section of the reporting.
         * See the Event Tracking Guide for more information.
         * 
         * @param objName The name of the tracked object.
         * @return A new event tracker instance.
         */
        public function createEventTracker( objName:String ):EventTracker
        {
            _debug.info( "createEventTracker( " + objName + " )" );
            return new EventTracker( objName, this );
        }
        
       /**
        * Constructs and sends the event tracking call to the Google Analytics Tracking Code. 
        * Use this to track visitor behavior on your website that is not related to a web page visit, 
        * such as interaction with a Flash video movie control or any user event that does not
        * trigger a page request. 
        * 
        * @param category The general event category (e.g. "Videos"). 
        * @param action The action for the event (e.g. "Play"). 
        * @param opt_label An optional descriptor for the event. 
        * @param opt_value An optional value to be aggregated with the event.
        * 
        * @return whether the event was sucessfully sent
        */
        /**
         * Constructs and sends the event tracking call to GATC.
         * 
         * @param eventType The type name for the event.
         * @param label An optional descriptor for the event.
         * @param value An optional value to be aggregated with the event.
         * 
         * @return whether the event was successfully sent.
         */
        public function trackEvent( category:String, action:String, label:String = null, value:Number = NaN ):Boolean
        {
            var success:Boolean = true;
            var params:int = 2;
            
            // If event tracking call is valid
            if( (category != "") && (action != "") )
            {
                // clear event tracker data
                _eventTracker.clearKey( EVENT_TRACKER_PROJECT_ID );
                _eventTracker.clearValue( EVENT_TRACKER_PROJECT_ID );
                
                // object / category
                success = _eventTracker.setKey( EVENT_TRACKER_PROJECT_ID,
                                                EVENT_TRACKER_OBJECT_NAME_KEY_NUM,
                                                category );
                
                // event type / action
                success = _eventTracker.setKey( EVENT_TRACKER_PROJECT_ID,
                                                EVENT_TRACKER_TYPE_KEY_NUM,
                                                action );
                
                if( label && label != "" )
                {
                    // event description / label
                    success = _eventTracker.setKey( EVENT_TRACKER_PROJECT_ID,
                                                    EVENT_TRACKER_LABEL_KEY_NUM,
                                                    label );
                    params = 3;
                    
                    // aggregate value
                    if( !isNaN(value) )
                    {
                        success = _eventTracker.setValue( EVENT_TRACKER_PROJECT_ID,
                                                          EVENT_TRACKER_VALUE_VALUE_NUM,
                                                          value );
                        params = 4;
                    }
                    
                }
                
                // event tracker is set successfully
                if( success )
                {
                    _debug.info( "valid event tracking call\ncategory: "+category+"\naction: "+action, VisualDebugMode.geek );
                    _sendXEvent( _eventTracker );
                }
                
            }
            else
            {
                // event tracking call is not valid, failed!
                _debug.warning( "event tracking call is not valid, failed!\ncategory: "+category+"\naction: "+action, VisualDebugMode.geek );
                success = false;
            }
            
            switch( params )
            {
                case 4:
                _debug.info( "trackEvent( " + [category,action,label,value].join( ", " ) + " )" );
                break;
                
                case 3:
                _debug.info( "trackEvent( " + [category,action,label].join( ", " ) + " )" );
                break;
                
                case 2:
                default:
                _debug.info( "trackEvent( " + [category,action].join( ", " ) + " )" );
            }
            
            return success;
        }
        
        
        // ----------------------------------------
        // Search Engines and Referrers
        // Methods that you use for customizing search engines and referral traffic in Google Analytics reporting.
        
        /**
         * Sets the string as ignored term(s) for Keywords reports.
         * Use this to configure Google Analytics to treat certain search terms as direct traffic,
         * such as when users enter your domain name as a search term.
         * When you set keywords using this method,
         * the search terms are still included in your overall page view counts,
         * but not included as elements in the Keywords reports.
         * 
         * @param newIgnoredOrganicKeyword Keyword search terms to treat as direct traffic.
         */
        public function addIgnoredOrganic(newIgnoredOrganicKeyword:String):void
        {
            _debug.info( "addIgnoredOrganic( " + newIgnoredOrganicKeyword + " )" );
            _config.organic.addIgnoredKeyword( newIgnoredOrganicKeyword );
        }
        
        /**
         * Excludes a source as a referring site.
         * Use this option when you want to set certain referring links as direct traffic,
         * rather than as referring sites.
         * 
         * For example, your company might own another domain that you want to track as
         * direct traffic so that it does not show up on the "Referring Sites" reports.
         * Requests from excluded referrals are still counted in your overall page view count.
         * 
         * @param newIgnoredReferrer Referring site to exclude.
         */
        public function addIgnoredRef(newIgnoredReferrer:String):void
        {
            _debug.info( "addIgnoredRef( " + newIgnoredReferrer + " )" );
            _config.organic.addIgnoredReferral( newIgnoredReferrer );
        }
        
        /**
         * Adds a search engine to be included as a potential search engine traffic source.
         * By default, Google Analytics recognizes a number of common search engines,
         * but you can add additional search engine sources to the list.
         * 
         * @param newOrganicEngine Engine for new organic source.
         * @param newOrganicKeyword Keyword name for new organic source.
         */
        public function addOrganic(newOrganicEngine:String, newOrganicKeyword:String):void
        {
            _debug.info( "addOrganic( " + [newOrganicEngine,newOrganicKeyword].join( ", " ) + " )" );
            _config.organic.addSource(newOrganicEngine, newOrganicKeyword);
        }
        
        /**
         * Clears all strings previously set for exclusion from the Keyword reports.
         */
        public function clearIgnoredOrganic():void
        {
            _debug.info( "clearIgnoredOrganic()" );
            _config.organic.clearIgnoredKeywords();
        }
        
        /**
         * Clears all items previously set for exclusion from the Referring Sites report.
         */
        public function clearIgnoredRef():void
        {
            _debug.info( "clearIgnoredRef()" );
            _config.organic.clearIgnoredReferrals();
        }
        
        /**
         * Clears all search engines as organic sources.
         * Use this method when you want to define a customized search engine ordering precedence.
         */
        public function clearOrganic():void
        {
            _debug.info( "clearOrganic()" );
            _config.organic.clearEngines();
        }
        
        /**
         * Gets the flag that indicates whether the browser tracking module is enabled.
         * See setClientInfo() for more information.
         * 
         * @return 1 if enabled, 0 if disabled.
         */
        public function getClientInfo():Boolean
        {
            _debug.info( "getClientInfo()" );
            return _config.detectClientInfo;
        }
        
        /**
         * Gets the Flash detection flag.
         * See setDetectFlash() for more information.
         * 
         * @return 1 if enabled, 0 if disabled.
         */
        public function getDetectFlash():Boolean
        {
            _debug.info( "getDetectFlash()" );
            return _config.detectFlash;
        }
        
        /**
         * Gets the title detection flag.
         * 
         * @return 1 if enabled, 0 if disabled.
         */
        public function getDetectTitle():Boolean
        {
            _debug.info( "getDetectTitle()" );
            return _config.detectTitle;
        }
        
        /**
         * Sets the browser tracking module.
         * By default, Google Analytics tracks browser information from your visitors
         * and provides more data about your visitor's browser settings that you get with a simple HTTP request.
         * If you desire, you can turn this tracking off by setting the parameter to false.
         * If you do this, any browser data will not be tracked and cannot be recovered
         * at a later date, so use this feature carefully.
         * 
         * @param enable Defaults to true, and browser tracking is enabled. If set to false, browser tracking is disabled.
         */
        public function setClientInfo(enable:Boolean):void
        {
            _config.detectClientInfo = enable;
            _debug.info( "setClientInfo( " + _config.detectClientInfo + " )" );
        }
        
        /**
         * Sets the Flash detection flag.
         * By default, Google Analytics tracks Flash player information from your visitors
         * and provides detailed data about your visitor's Flash player settings.
         * If you desire, you can turn this tracking off by setting the parameter to false.
         * If you do this, any Flash player data will not be tracked and cannot be recovered
         * at a later date, so use this feature carefully.
         * 
         * @param enable Default is true and Flash detection is enabled. False disables Flash detection.
         */
        public function setDetectFlash(enable:Boolean):void
        {
            _config.detectFlash = enable;
            _debug.info( "setDetectFlash( " + _config.detectFlash + " )" );
        }
        
        /**
         * Sets the title detection flag.
         * By default, page title detection for your visitors is on.
         * This information appears in the Contents section under "Content by Title."
         * If you desire, you can turn this tracking off by setting the parameter to false.
         * You could do this if your website has no defined page titles and the Content by
         * Title report has all content grouped into the "(not set)" list.
         * You could also turn this off if all your pages have particularly long titles.
         * If you do this, any page titles that are defined in your website will not
         * be displayed in the "Content by Title" reports.
         * This information cannot be recovered at a later date once it is disabled.
         * 
         * @param enable Defaults to true, and title detection is enabled. If set to false, title detection is disabled.
         */
        public function setDetectTitle(enable:Boolean):void
        {
            _config.detectTitle = enable;
            _debug.info( "setDetectTitle( " + _config.detectTitle + " )" );
        }
        
        // ----------------------------------------
        // Urchin Server
        // Methods that you use for configuring your server setup when you are using
        // both Google Analytics and the Urchin software to track your website.
        
        /**
         * Gets the local path for the Urchin GIF file.
         * See setLocalGifPath() for more information.
         * 
         * @return Path to GIF file on the local server.
         */
        public function getLocalGifPath():String
        {
            _debug.info( "getLocalGifPath()" );
            return _config.localGIFpath;
        }
        
        /**
         * Returns the server operation mode.
         * Possible return values are 0 for local mode (sending data to local server set by setLocalGifPath()),
         * 1 for remote mode (send data to Google Analytics backend server), or 2 for both local and remote mode.
         * 
         * @return  Server operation mode.
         */
        public function getServiceMode():ServerOperationMode
        {
            _debug.info( "getServiceMode()" );
            return _config.serverMode;
        }
        
        /**
         * Sets the local path for the Urchin GIF file.
         * Use this method if you are running the Urchin tracking software on your local servers.
         * The path you specific here is used by the setLocalServerMode() and setLocalRemoteServerMode()
         * methods to determine the path to the local server itself.
         * 
         * @param newLocalGifPath Path to GIF file on the local server.
         */
        public function setLocalGifPath(newLocalGifPath:String):void
        {
            _config.localGIFpath = newLocalGifPath;
            _debug.info( "setLocalGifPath( " + _config.localGIFpath + " )" );
        }
        
        /**
         * Invoke this method to send your tracking data both to a local server
         * and to the Google Analytics backend servers.
         * You would use this method if you are running the Urchin tracking software
         * on your local servers and want to track data locally as well as via Google Analytics servers.
         * In this scenario, the path to the local server is set by setLocalGifPath().
         */
        public function setLocalRemoteServerMode():void
        {
            _config.serverMode = ServerOperationMode.both;
            _debug.info( "setLocalRemoteServerMode()" );
        }
        
        /**
         * Invoke this method to send your tracking data to a local server only.
         * You would use this method if you are running the Urchin tracking software on your local servers
         * and want all tracking data to be sent to your servers.
         * In this scenario, the path to the local server is set by setLocalGifPath().
         */
        public function setLocalServerMode():void
        {
            _config.serverMode = ServerOperationMode.local;
            _debug.info( "setLocalServerMode()" );
        }
        
        /**
         * Default installations of Google Analytics send tracking data to the Google Analytics server.
         * You would use this method if you have installed the Urchin software for your website
         * and want to send particular tracking data only to the Google Analytics server.
         */
        public function setRemoteServerMode():void
        {
            _config.serverMode = ServerOperationMode.remote;
            _debug.info( "setRemoteServerMode()" );
        }
        
    }
}