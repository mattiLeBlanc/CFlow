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

	/**
	 * Constructor.
	 * type				url or event; determines which parameters are expected
	 * parameters		if the type is url, a url key is required; for event, target and event keys are optional
	 * 					additionally, for both types a parameters struct is optional, which contains additional querystring parameters
	 * permanent		whether this is a permanent redirect or not
	 * requestStrategy	the request strategy, only required when type is event
	 **/
	public void function init(required string type, required struct parameters = {}, boolean permanent = false, RequestStrategy requestStrategy) {

		variables.type = arguments.type;

		switch (variables.type) {
			case "url":
				// the url key should be present
				variables.urlString = new cflow.util.Parameter(arguments.parameters.url);
				break;

			case "event":
				variables.urlString = new cflow.util.Parameter("");

				// the request strategy should be present, target and event keys are optional in parameters
				variables.requestStrategy = arguments.requestStrategy;
				variables.target = StructKeyExists(arguments.parameters, "target") ? arguments.parameters.target : "";
				variables.event = StructKeyExists(arguments.parameters, "event") ? arguments.parameters.event : "";
				break;
		}

		// handle runtime parameters if present
		local.parameters = {};
		for (var name in arguments.parameters) {
			// store the parameter in a Parameter instance; that instance will determine whether the value should be taken literally or be evaluated
			local.parameters[name] = new cflow.util.Parameter(arguments.parameters[name]);
		}
		variables.parameters = local.parameters;

		if (StructIsEmpty(variables.parameters)) {
			// no runtime parameters
			if (variables.type == "event") {
				// the url is always the same, so we can generate it now
				variables.urlString = arguments.requestStrategy.writeUrl(variables.target, variables.event);
			}
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

	public string function getType() {
		return "redirect";
	}

	private string function obtainUrl(required Event event) {

		var urlString = variables.urlString.getValue(arguments.event);

		if (!StructIsEmpty(variables.parameters)) {
			// we have to append runtime parameters onto the url
			var parameters = {};
			for (var name in variables.parameters) {
				// get the value using the event
				parameters[name] = variables.parameters[name].getValue(arguments.event);
			}

			switch (variables.type) {
				case "url":
					if (urlString does not contain "?") {
						urlString &= "?";
					}
					var queryString = "";
					for (var name in parameters) {
						queryString = ListAppend(queryString, name & "=" & UrlEncodedFormat(parameters[name]), "&");
					}
					urlString &= queryString;

					break;

				case "event":
					urlString = variables.requestStrategy.writeUrl(variables.target, variables.event, parameters);
					break;
			}
		}

		return urlString;
	}

}