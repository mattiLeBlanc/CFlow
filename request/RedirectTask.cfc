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

component RedirectTask implements="Task" {

	public void function init(required string type, required struct parameters = {}, boolean permanent = false, RequestManager requestManager) {

		switch (arguments.type) {
			case "url":
				// the url key should be present
				variables.urlString = arguments.parameters.url;
				variables.generate = false;
				break;

			case "event":

				variables.urlString = "";
				variables.generate = true; // do we have to generate the url at runtime?

				// the request manager should be present, as well as some keys in the parameters struct
				variables.requestManager = arguments.requestManager;
				variables.target = arguments.parameters.target;
				variables.event = arguments.parameters.event;
				// any other keys in the parameters struct are (fixed) url parameters
				variables.parameters = StructCopy(arguments.parameters);
				// remove the required arguments from the parameters
				StructDelete(variables.parameters, "target");
				StructDelete(variables.parameters, "event");
				StructDelete(variables.parameters, "permanent");

				// handle runtime parameters if present
				if (StructKeyExists(variables.parameters, "parameters")) {
					// this should be an array of parameter names that have to be evaluated at runtime
					variables.runtimeParameters = variables.parameters.parameters;
					StructDelete(variables.parameters, "parameters");
				} else {
					// no runtime parameters
					// the url is always the same, so we can generate it now
					variables.urlString = arguments.requestManager.writeUrl(arguments.parameters.target, arguments.parameters.event, variables.parameters);
					variables.generate = false;
				}
				break;
		}

		if (arguments.permanent) {
			variables.statusCode = 301;
		} else {
			variables.statusCode = 302;
		}

	}

	public boolean function run(required Event event) {

		Location(obtainUrl(arguments.event), false, variables.statusCode);

		return true;
	}

	private string function obtainUrl(required Event event) {

		var urlString = variables.urlString;

		if (variables.generate) {
			// this means we have to append runtime parameters onto the url
			var parameters = StructCopy(variables.parameters);
			for (var parameter in variables.runtimeParameters) {
				if (StructKeyExists(arguments.event, parameter)) {
					parameters[parameter] = arguments.event[parameter];
				}
			}
			urlString = variables.requestManager.writeUrl(variables.target, variables.event, parameters);
		}

		return urlString;
	}

}