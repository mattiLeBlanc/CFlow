/*
   Copyright 2012 Neo Neo

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

component DefaultRequestManager implements="RequestManager" accessors="true" {

	property name="defaultTarget" type="string" default="";
	property name="defaultEvent" type="string" default="";

	public void function init(required Context context) {

		variables.context = context;

	}

	public string function writeUrl(required string target, required string event, struct parameters) {

		var urlString = "index.cfm?target=#arguments.target#&event=#arguments.event#";

		if (StructKeyExists(arguments, "parameters")) {
			for (var name in arguments.parameters) {
				urlString = ListAppend(urlString, name & "=" & arguments.parameters[name], "&");
			}
		}

		return urlString;
	}

	/**
	 * Default request handling implementation.
	 *
	 * The parameter values in the url and form scopes are collected as properties for the event.
	 * The target and event parameters are used to dispatch the corresponding event.
	 * If no target or event parameters are present, the default values for these parameters are used.
	 **/
	public Response function handleRequest() {

		var properties = StructCopy(url);
		StructAppend(properties, form, false);

		var targetName = "";
		var eventType = "";
		if (StructKeyExists(properties, "target")) {
			targetName = properties.target;
		} else {
			targetName = getDefaultTarget();
		}
		if (StructKeyExists(properties, "event")) {
			eventType = properties.event;
		} else {
			eventType = getDefaultEvent();
		}

		// tell the context what to do
		return variables.context.handleEvent(targetName, eventType, properties);
	}

}