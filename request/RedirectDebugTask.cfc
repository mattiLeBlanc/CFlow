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

component RedirectDebugTask extends="RedirectTask" {

	public void function run(required Event event) {

		// we just record the fact that normally a redirect should occur right now
		arguments.event.record({
			url = obtainUrl(arguments.event)
		}, "cflow.redirect");
		// abort the rest of the flow
		arguments.event.abort();

	}

}