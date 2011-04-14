//
// easyXDM
// http://easyxdm.net/
// Copyright(c) 2009-2011, Øyvind Sean Kinsey, oyvind@kinsey.no.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//



/* Security model:
 * SWF's must be loaded from the same domain as the page, origin verification is ensure by using domain prefixed channel names and a whitelist when listening
 * */

import flash.external.ExternalInterface;
import System.security;

/**
 * This class facilitates flash based communication between domains.
 * @author Øyvind Sean Kinsey
 */
class Main 
{	
	// docs at http://livedocs.adobe.com/flash/9.0/main/wwhelp/wwhimpl/js/html/wwhelp.htm
	public static function main(swfRoot:MovieClip):Void 

	{	
		// LocalConnection has a max length 
		var maxMessageLength = 40000;
		
		// map of all the senders
		var sendMap = { };
		
		// set up the prefix as a string based accessor to remove the risk of XSS
		var prefix:String = _root.ns ? ("window[\"" + _root.ns.split(".").join("\"][\"") + "\"].") : "";
		var tracer:String = _root.log;
		
		// this will be our origin
		var origin = _root.proto + "//" + _root.domain;
		
		// set up the logger, if any
		var log = _root.log =="true" ? function(msg) {
			ExternalInterface.call(prefix + "easyXDM.Debug.trace", " swf: " + msg);
		} : function() {
		};

		// add the postMessage method
		ExternalInterface.addCallback("postMessage", { }, function(channel:String, message:String) {
			sendMap[channel](message);
		});
		
		// add the createChannel method
		ExternalInterface.addCallback("createChannel", { }, function(channel:String, remoteOrigin:String, isHost:Boolean) {
			log("creating channel " + channel);
			
			// get the remote domain
			var remoteDomain = remoteOrigin.substr(remoteOrigin.indexOf("://") + 3), if (remoteDomain.indexOf(":") != -1) remoteDomain = remoteDomain.substr(0, remoteDomain.indexOf(":"));
			
			// AS2 only uses the superdomain when generating the channelname
			var remoteSuperDomain = remoteDomain.split(".").reverse().splice(0, 2).reverse().join(".");
			
			// the sending channel has the domain prepended so that only this domain can receive the message
			var sendingChannelName =  remoteSuperDomain + ":" + channel + "_" +  (isHost ? "_consumer" : "_provider");
			var receivingChannelName = channel + "_" + (isHost ? "_provider" : "_consumer");	
			
			// set up the sending connection and store it in the map
			var sendingConnection:LocalConnection = new LocalConnection();
			sendMap[channel] = function(message) {
				log("sending to " + sendingChannelName + ", length is " + message.length);
				
				var fragments = [], fragment, length = message.length, pos = 0;
				while (pos <= length) {
					fragment = message.substr(pos, maxMessageLength);;
					pos += maxMessageLength;
					log("fragmentlength: " + fragment.length + ", remaining: " + (length - pos))
					if (!sendingConnection.send(sendingChannelName, "onMessage", fragment, length - pos)) {
						log("sending failed");
					}
				}
			};	

			// set up the listening connection
			var listeningConnection:LocalConnection  = new LocalConnection();
			if (isHost) {
				// the host must delay calling channel_init until the other end is ready
				listeningConnection.ready = function() {
					ExternalInterface.call(prefix + "easyXDM.Fn.get(\"flash_" + channel + "_init\")");	
				};
			}
			
			// set up the onMessage handler - this combines fragmented messages
			var incommingFragments = [];
			listeningConnection.onMessage = function(message, remaining) {
				incommingFragments.push(message);
				if (remaining <= 0) {
					log("received final fragment");	
					// escape \\ and pass on 
					ExternalInterface.call(prefix + "easyXDM.Fn.get(\"flash_" + channel + "_onMessage\")", incommingFragments.join("").split("\\").join("\\\\"), remoteOrigin);
					incommingFragments = [];
				}else {
					log("received fragment, length is " + message.length + " remaining is " + remaining);	
				}
			};
						
			// allow messages only from the expected domain
			listeningConnection.allowDomain = function(domain) {
				return domain == remoteDomain;
			};
			
			// connect 
			// http://livedocs.adobe.com/flash/9.0/main/wwhelp/wwhimpl/js/html/wwhelp.htm
			if (listeningConnection.connect(receivingChannelName)) {
				log("listening on " + receivingChannelName);	
			} else {
				log("could not listen on " + receivingChannelName);	
			}
			
			// start the channel
			if (!isHost) {
				sendingConnection.send(sendingChannelName, "ready");
				ExternalInterface.call(prefix + "easyXDM.Fn.get(\"flash_" + channel + "_init\")");	
			}
		});
		
		// add the destroyChannel method
		ExternalInterface.addCallback("destroyChannel", { }, function(channel:String) {
			delete sendMap[channel];
		});
		
		// kick things off
		log("calling init");
		ExternalInterface.call(prefix + "easyXDM.Fn.get(\"flash_loaded\")");		
	}
}