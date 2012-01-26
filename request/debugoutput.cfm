<cfsilent>
	<cffunction name="construct" output="false" returntype="struct" hint="Constructs the task hierarchy from the messages array.">
		<cfargument name="children" type="array" required="true" hint="The array wherein to collect task data.">

		<!--- the messages and index variables are present in the template scope, so they are not local --->

		<cfset var data = {}>
		<cfset ArrayAppend(arguments.children, data)>

		<cfset data.element = messages[index]><!--- we loop until we find the corresponding item --->
		<!--- only certain messages can contain children --->
		<cfif REFind("(task|(start|before|after|end|event)Tasks)", data.element.message) eq 1>
			<cfset index++>
			<cfset data.children = []>
			<cfloop condition="index lte ArrayLen(messages)">
				<cfif structEquals(messages[index], data.element)>
					<cfbreak>
				</cfif>
				<cfset construct(data.children)>
				<cfset index++>
			</cfloop>
			<!--- task duration --->
			<!--- when debug is rendered when an exception is thrown, the array is not complete so we cannot assume that the element exists --->
			<cfif ArrayLen(messages) gte index>
				<cfset data.duration = messages[index].tickcount - data.element.tickcount>
			</cfif>
		</cfif>

		<cfreturn data>
	</cffunction>

	<cffunction name="structEquals" output="false" returntype="boolean">
		<cfargument name="struct1" type="struct" required="true">
		<cfargument name="struct2" type="struct" required="true">

		<cfset var key = "">
		<cfset var isEqual = true>
		<cfloop collection="#arguments.struct1#" item="key">
			<!--- ignore tickcount --->
			<cfif key neq "tickcount">
				<cfif StructKeyExists(arguments.struct2, key)>
					<cfif IsSimpleValue(arguments.struct1[key])>
						<cfset isEqual = arguments.struct1[key] eq arguments.struct2[key]>
					<cfelse>
						<!--- we expect this to be a struct --->
						<cfset isEqual = structEquals(arguments.struct1[key], arguments.struct2[key])>
					</cfif>
				<cfelse>
					<cfset isEqual = false>
				</cfif>

				<cfif not isEqual>
					<cfbreak>
				</cfif>
			</cfif>
		</cfloop>

		<cfreturn isEqual>
	</cffunction>

	<cffunction name="render" output="false" returntype="string">
		<cfargument name="data" type="struct" required="true">

		<cfset var child = "">
		<cfset var content = "">
		<cfset var message = data.element.message>
		<cfset var metadata = data.element.metadata>
		<cfset var renderChildren = false>
		<cfset var renderException = false>
		<cfset var dumpMetadata = false>

		<cfset var className = REReplace(message, "\s", "-", "all")>
		<cfif message eq "task">
			<cfset var type = ListLast(metadata.type, ".")>
			<!--- cut off "Task" and make lower case --->
			<cfset className &= " " & LCase(Left(type, Len(type) - 4))>
		<cfelseif REFind("(start|before|after|end|event)Tasks", message) eq 1>
			<cfset className &= " phase">
		</cfif>

		<cfsavecontent variable="content">
			<cfoutput>
			<li class="#className#">
				<div class="message">
					<cfswitch expression="#message#">
						<cfcase value="startTasks">Start</cfcase>
						<cfcase value="beforeTasks">Before</cfcase>
						<cfcase value="afterTasks">After</cfcase>
						<cfcase value="endTasks">End</cfcase>
						<cfcase value="eventTasks">Event</cfcase>
						<cfcase value="eventCanceled">Event #data.element.target#.#data.element.event# canceled</cfcase>
						<cfcase value="task">
							<cfswitch expression="#type#">
								<cfcase value="InvokeTask">Invoke #metadata.controllerName#.#metadata.methodName#</cfcase>
								<cfcase value="DispatchTask">Dispatch #metadata.targetName#.#metadata.eventType#</cfcase>
								<cfcase value="RenderTask">Render #metadata.template#</cfcase>
							</cfswitch>
						</cfcase>
						<cfcase value="exception">
							Exception
							<cfset renderException = true>
						</cfcase>
						<cfdefaultcase>
							#message#
							<!--- dump metadata if we don't know what it's about --->
							<cfset dumpMetadata = true>
						</cfdefaultcase>
					</cfswitch>
					<cfif StructKeyExists(data, "duration")>
						<span class="duration">#data.duration#</span>
					</cfif>
				</div>
				<cfset dumpMetadata = dumpMetadata and not StructIsEmpty(metadata)>
				<cfset renderChildren = StructKeyExists(data, "children") and not ArrayIsEmpty(data.children)>
				<cfif dumpMetadata or renderChildren or renderException>
					<div class="data">
						<cfif renderChildren>
							<ul>
							<cfloop array="#data.children#" index="child">
								#render(child)#
							</cfloop>
							</ul>
						</cfif>
						<cfif renderException>
							<cfset var exception = metadata.exception>
							<h2>#exception.type#: #exception.message#</h2>
							<p><strong>#exception.detail#</strong></p>

							<!--- stack trace --->
							<cfset var tagContext = exception.tagContext>
							<cfset var i = 0>
							<p><strong>#tagContext[1].template#: line #tagContext[1].line#</strong></p>
							<code>#tagContext[1].codePrintHTML#</code>
							<p>
								<cfloop from="2" to="#ArrayLen(tagContext)#" index="i">
								<div>#tagContext[i].template#: line #tagContext[i].line#</div>
								</cfloop>
							</p>
						</cfif>
						<cfif dumpMetadata>
							<cfdump var="#metadata#">
						</cfif>
					</div>
				</cfif>
			</li>
			</cfoutput>
		</cfsavecontent>

		<cfreturn content>
	</cffunction>

	<!--- construct the task hierarchy --->
	<cfset messages = properties._messages>
	<cfset index = 1>
	<cfset result = []>
	<cfloop condition="index lte ArrayLen(messages)">
		<cfset construct(result)>
		<cfset index++>
	</cfloop>
</cfsilent>

<!--- output the results --->
<style type="text/css">
	#cflow {
		font-family: Verdana, sans-serif;
		font-size: 9pt;
	}

	#cflow > h1 {
		font-weight: bold;
		font-size: 12pt;
	}

	#cflow ul {
		list-style-type: none;
		margin: 0;
		padding: 0 12px 0 12px;
	}

	#cflow li {
		padding: 0px;
		border: 2px dashed transparent;
	}

	#cflow .duration {
		font-weight: bold;
		float: right;
	}

	#cflow .message, #cflow .data {
		border: 1px solid black;
		padding: 2px;
	}

	#cflow .message {
		overflow: hidden;
		background-color: rgb(255, 178, 0);
	}

	#cflow .data {
		margin-top: 1px;
	}

	#cflow .phase > .message {
		background-color: rgb(153, 204, 51);
		font-weight: bold;
	}

	#cflow .phase > .data {
		background-color: rgb(204, 255, 51);
		font-weight: bold;
	}

	#cflow .task > .message {
		background-color: rgb(153, 153, 255);
		font-weight: normal;
	}

	#cflow .task > .data {
		background-color: rgb(204, 204, 255);
		font-weight: normal;
	}

	#cflow .eventCanceled > .message {
		background-color: rgb(255, 102, 0);
	}

	#cflow .exception > .message {
		background-color: rgb(220, 50, 47);
		font-weight: bold;
		color: white;
	}

	#cflow .exception > .data {
		background-color: rgb(255, 204, 0);
	}

	#cflow .exception h2 {
		font-size: 11pt;
	}
</style>

<cfoutput>
<div id="cflow">
	<h1>CFlow debugging information</h1>
	<ul>
	<cfloop array="#result#" index="child">
		#render(child)#
	</cfloop>
	</ul>
</div>
</cfoutput>

<script>
	var cflow = {

		node: document.getElementById("cflow"),

		getActiveListItem: function (node) {
			var listItem = node;

			while (listItem.tagName.toLowerCase() !== "li" && listItem !== this.node) {
				listItem = listItem.parentNode;
			}

			if (listItem === this.node) {
				listItem = null;
			}

			return listItem;
		}

	};

	cflow.node.addEventListener("mouseover", function (e) {
		var listItem = cflow.getActiveListItem(e.target);
		if (listItem) {
			listItem.style.borderColor = "red";
		}
	}, false);

	cflow.node.addEventListener("mouseout", function (e) {
		var listItem = cflow.getActiveListItem(e.target);
		if (listItem) {
			listItem.style.borderColor = "";
		}
	}, false);

	cflow.node.addEventListener("click", function (e) {
		var listItem = cflow.getActiveListItem(e.target);
		if (listItem) {
			var dataDiv = listItem.children[1];
			if (dataDiv) {
				dataDiv.style.display = dataDiv.style.display === "none" ? "" : "none";
			}
		}
	}, false);

</script>
