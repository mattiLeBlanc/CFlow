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

component XmlReader {

	variables.tasks = {}; // lists of tasks per target
	variables.abstractTargetNames = []; // list of targets that are abstract
	variables.defaultControllers = {}; // default controllers per target

	variables.complexTaskTypes = ["invoke", "dispatch", "if", "else"]; // complex tasks are tasks that can contain other tasks

	public void function init(required Context context) {
		variables.context = arguments.context;
	}

	public struct function read(required string path) {

		local.path = ExpandPath(arguments.path);
		local.list = DirectoryList(local.path, true, "name", "*.xml");

		for (var fileName in list) {
			readFile(local.path & "/" & fileName);
		}

		return variables.tasks;
	}

	public void function register() {

		// use the target as the view directory name for start, before, after, and end tasks only (argument false)
		setViewDirectories(false);

		// process all include nodes
		compileIncludes();

		// set all invoke tasks' controllers without a controller to the default controller of the target
		setDefaultControllers();

		// all dispatch and redirect tasks without a target will go to the target that owns the event
		setDefaultDispatchTargets();
		setDefaultRedirectTargets();

		// use the target name as the directory name for event tasks
		// so an included event will look for its views in the receiving target's directory
		setViewDirectories(true);

		// throw away the abstract targets
		// if we don't do this, the framework will try to create objects, which is unnecessary, and might result in exceptions
		removeAbstractTargets();

		var phases = ["start", "end", "before", "after"];
		// variables.tasks is a struct where each key is a target name
		for (var name in variables.tasks) {

			var tasks = variables.tasks[name];
			// tasks contains all the tasks for this target, stored by phase and by event
			// first create tasks for all phases
			for (var phase in phases) {
				// always create the task, even if it remains empty, because otherwise the task is created for each request later
				if (StructKeyExists(tasks, phase)) {
					for (var task in tasks[phase]) {
						// register the task for the current phase under the target name
						variables.context.register(createTask(task), phase, name);
					}
				}
			}

			tasks = tasks.events;
			// tasks is now a struct where keys are event types
			for (var type in tasks) {
				// loop over the tasks for this event and create subtasks
				for (var task in tasks[type]) {
					// register the task for the given event
					variables.context.register(createTask(task), "event", name, type);
				}
			}
		}

		// purge all collected information so that if new reads happen, they are not linked to these tasks
		variables.tasks = {};
		variables.defaultControllers = {};

	}

	private void function readFile(required string path) {

		var content = FileRead(arguments.path);
		var xmlDocument = XmlParse(content, false);

		// the root element can be targets or target
		switch (xmlDocument.xmlRoot.xmlName) {
			case "targets":
				// get all targets and create task definitions
				var targets = xmlDocument.xmlRoot.xmlChildren;
				for (var target in targets) {
					getTasksFromTargetNode(target);
				}
				break;

			case "target":
				getTasksFromTargetNode(xmlDocument.xmlRoot);
				break;
		}

	}

	private void function getTasksFromTargetNode(required xml node) {

		var name = arguments.node.xmlAttributes.name;

		if (StructKeyExists(arguments.node.xmlAttributes, "abstract") && arguments.node.xmlAttributes.abstract) {
			// abstract target
			ArrayAppend(variables.abstractTargetNames, name);
		}

		// the node may have an attribute default controller
		if (StructKeyExists(arguments.node.xmlAttributes, "defaultcontroller")) {
			variables.defaultControllers[name] = arguments.node.xmlAttributes.defaultcontroller;
		}

		var tasks = {};
		for (var tagName in ["start", "end", "before", "after"]) {
			var nodes = XmlSearch(arguments.node, tagName);
			// we expect at most 1 node of this type
			if (!ArrayIsEmpty(nodes)) {
				tasks[tagName] = getTasksFromChildNodes(nodes[1]);
			}
		}

		tasks["events"] = {};
		var eventNodes = XmlSearch(arguments.node, "event");
		for (var eventNode in eventNodes) {
			tasks.events[eventNode.xmlAttributes.type] = getTasksFromChildNodes(eventNode);
		}

		var includeNodes = XmlSearch(arguments.node, "include");
		if (!ArrayIsEmpty(includeNodes)) {
			// create an array that will contain the includes in reverse source order
			// the first include's tasks must be executed first, so they must be created last (see compileIncludes)
			tasks["includes"] = [];
			for (var includeNode in includeNodes) {
				ArrayPrepend(tasks.includes, includeNode.xmlAttributes);
			}
		}

		variables.tasks[name] = tasks;

	}

	private struct function getTaskFromNode(required xml node) {

		var task = {
			"$type" = arguments.node.xmlName
		};
		// we assume the xml is correct, so we can just append the attributes
		StructAppend(task, arguments.node.xmlAttributes);

		// for complex tasks, there can be child tasks that are to be executed if an event is canceled
		if (ArrayContains(variables.complexTaskTypes, task.$type)) {
			task["sub"] = getTasksFromChildNodes(arguments.node);
		}

		return task;
	}

	private array function getTasksFromChildNodes(required xml node) {

		var tasks = [];
		var childNodes = arguments.node.xmlChildren;

		for (var childNode in childNodes) {
			ArrayAppend(tasks, getTaskFromNode(childNode));
		}

		return tasks;
	}

	private void function compileIncludes() {

		var targets = StructFindKey(variables.tasks, "includes", "all");

		// there can be includes that include other includes
		// therefore, we repeat the search for include keys until we find none
		// we know the total number of includes, so if we need to repeat the loop more than that number of times, there is a circular reference
		var count = ArrayLen(targets);
		while (!ArrayIsEmpty(targets)) {
			for (var target in targets) {
				// include.value contains an array of includes
				var includes = Duplicate(target.value); // we make a duplicate, because we are going to remove items from the original array
				for (var include in includes) {
					// get the tasks that belong to this include
					if (!StructKeyExists(variables.tasks, include.target)) {
						Throw(type = "cflow.request", message = "Included target '#include.target#' not found");
					}
					var includeTarget = variables.tasks[include.target];
					// if the target has includes, we have to wait until those are resolved
					// that will happen in a following loop
					if (!StructKeyExists(includeTarget, "includes")) {
						if (StructKeyExists(include, "event")) {
							// an event is specified, only include it if that event is not already defined on the receiving target
							if (!StructKeyExists(target.owner.events, include.event)) {
								if (StructKeyExists(includeTarget.events, include.event)) {
									// the owner key contains a reference to the original tasks struct, so we can modify it
									target.owner.events[include.event] = Duplicate(includeTarget.events[include.event]);
								} else {
									Throw(type = "cflow.request", message = "Event '#include.event#' not found in included target '#include.target#'");
								}
							}
						} else {
							// the whole task list of the given target must be included
							// if there are start or before tasks, they have to be prepended to the existing start and before tasks, respectively
							for (var type in ["start", "before"]) {
								if (StructKeyExists(includeTarget, type)) {
									// duplicate the task array, since it may be modified later when setting the default controller
									var typeTasks = Duplicate(includeTarget[type]);
									if (StructKeyExists(target.owner, type)) {
										// append the existing tasks
										for (task in target.owner[type]) {
											ArrayAppend(typeTasks, task);
										}
									}
									target.owner[type] =  typeTasks;
								}
							}
							// for end or after tasks, it's the other way around: we append those tasks to the array of existing tasks
							for (var type in ["after", "end"]) {
								if (StructKeyExists(includeTarget, type)) {
									var typeTasks = Duplicate(includeTarget[type]);
									if (!StructKeyExists(target.owner, type)) {
										target.owner[type] = [];
									}
									for (task in typeTasks) {
										ArrayAppend(target.owner[type], task);
									}
								}
							}

							// now include all events that are not yet defined on this target
							StructAppend(target.owner.events, Duplicate(includeTarget.events), false);

						}
						// this include is now completely processed, remove it from the original array
						ArrayDeleteAt(target.value, 1); // it is always the first item in the array
					} else {
						// this include could not be processed because it has includes itself
						// we cannot process further includes, the order is important
						break;
					}
				}

				// if all includes were processed, there are no items left in the includes array
				if (ArrayIsEmpty(target.value)) {
					StructDelete(target.owner, "includes");
				}
			}

			count--;
			if (count < 0) {
				Throw(type = "cflow.request", message = "Circular reference detected in includes");
			}

			targets = StructFindKey(variables.tasks, "includes", "all");
		}

	}

	/**
	 * Sets the controllers explicitly to each invoke task, if possible.
	 **/
	private void function setDefaultControllers() {

		for (var name in variables.tasks) {
			var target = variables.tasks[name];

			// if a default controller was specified, set it on all invoke tasks that have no controller
			if (StructKeyExists(variables.defaultControllers, name)) {
				// find all tasks that have no controller specified
				var tasks = StructFindValue(target, "invoke", "all");
				for (var task in tasks) {
					if (task.owner.$type == "invoke") {
						if (!StructKeyExists(task.owner, "controller")) {
							// explicitly set the controller
							task.owner["controller"] = variables.defaultControllers[name];
						}
					}
				}
			}
		}

	}

	/**
	 * Sets default targets for dispatch tasks that have not specified it.
	 **/
	private void function setDefaultDispatchTargets() {

		for (var name in variables.tasks) {
			var target = variables.tasks[name];

			// for dispatch task with no target use the current target
			var tasks = StructFindValue(target, "dispatch", "all");
			for (var task in tasks) {
				if (task.owner.$type == "dispatch") {
					if (!StructKeyExists(task.owner, "target")) {
						task.owner["target"] = name;
					}
					// if the event goes to the same target, and is defined immediately in the before or after phase, this would cause an infinite loop
					if (task.owner.target == name && (task.path contains ".before[" or task.path contains ".after[") && task.path does not contain ".sub[") {
						Throw(
							type = "cflow.request",
							message = "Dispatching event '#task.owner.event#' to the current target '#name#' will cause an infinite loop",
							detail = "Do not define dispatch tasks without a target in the before or after phases, unless the task is run conditionally"
						);
					}
				}

			}

		}

	}

	/**
	 * Modifies the view name so it uses the target name as the directory (within the view mapping).
	 * The boolean argument specifies if the change is applied to render tasks in event phases (true) or in the other phases (false).
	 * This is important when targets with render tasks are included.
	 * If the render task is defined in an event, the receiving target has to implement that view.
	 * If the render task is defined elsewhere, the originating target has to implement it.
	 **/
	private void function setViewDirectories(required boolean eventPhase) {

		for (var name in variables.tasks) {
			var target = variables.tasks[name];

			var tasks = StructFindValue(target, "render", "all");
			for (task in tasks) {
				if (task.owner.$type == "render") {
					if (arguments.eventPhase && task.path contains ".events." || !arguments.eventPhase && task.path does not contain ".events.") {
					// check for the existence of a view attribute, as some other task could have an attribute with the value 'render'
						// prepend the target name as the directory name
						task.owner.view = name & "/" & task.owner.view;
					}
				}
			}
		}

	}

	/**
	 * Sets default targets for redirect tasks that have not specified it.
	 **/
	private void function setDefaultRedirectTargets() {

		for (var name in variables.tasks) {
			var target = variables.tasks[name];

			// for dispatch task with no target use the current target
			var tasks = StructFindValue(target, "redirect", "all");
			for (var task in tasks) {
				if (task.owner.$type == "redirect") {
					// do nothing if the redirect is to a fixed url, or if it has a target already
					if (!StructKeyExists(task.owner, "url")) {
						if (!StructKeyExists(task.owner, "target")) {
							task.owner["target"] = name;
						}

						// if the redirect goes to the same target and is defined outside the event phase, this would cause an infinite loop
						if (task.owner.target == name && task.path does not contain ".events." && task.path does not contain ".sub[") {
							Throw(
								type = "cflow.request",
								message = "Redirecting to event '#task.owner.event#' on the current target '#name#' will cause an infinite loop",
								detail = "Do not define redirect tasks without a target outside the event phase, unless the task is run conditionally"
							);
						}
					}
				}
			}

		}

	}

	private void function removeAbstractTargets() {

		for (var name in variables.abstractTargetNames) {
			StructDelete(variables.tasks, name);
		}

	}

	private Task function createTask(struct task) {

		var instance = JavaCast("null", 0);

		if (!StructKeyExists(arguments, "task")) {
			instance = arguments.context.createPhaseTask();
		} else {
			switch (arguments.task.$type) {
				case "invoke":
					if (!StructKeyExists(arguments.task, "controller")) {
						Throw(type = "cflow.request", message = "No controller associated with invoke task for method '#arguments.task.method#'");
					}
					instance = variables.context.createInvokeTask(arguments.task.controller, arguments.task.method);
					break;

				case "dispatch":
					instance = variables.context.createDispatchTask(arguments.task.target, arguments.task.event);
					break;

				case "render":
					instance = variables.context.createRenderTask(arguments.task.view);
					break;

				case "redirect":
					var permanent = false;
					if (StructKeyExists(arguments.task, "permanent")) {
						permanent = arguments.task.permanent;
					}

					var parameters = StructCopy(arguments.task);
					StructDelete(parameters, "permanent");
					StructDelete(parameters, "$type");

					// there are two types of redirects: to an event and to a url
					// depending on the type, the constructor expects different parameters
					var type = "event";
					if (StructKeyExists(arguments.task, "url")) {
						// the redirect should be to the url defined here
						type = "url";
					} else {
						// we have a redirect to an event
						// if there is a parameters attribute present, convert the value to an array
						if (StructKeyExists(parameters, "parameters")) {
							parameters.parameters = ListToArray(parameters.parameters);
						}
					}

					instance = variables.context.createRedirectTask(type, parameters, permanent);
					break;

				case "if":
					instance = variables.context.createIfTask(arguments.task.condition);
					break;

				case "else":
					var condition = StructKeyExists(arguments.task, "condition") ? arguments.task.condition : "";
					instance = variables.context.createElseTask(condition);
					break;

				case "set":
					// the variable name is the first (and only) attribute
					var attributes = StructCopy(arguments.task);
					var overwrite = !StructKeyExists(arguments.task, "overwrite") || arguments.task.overwrite;
					StructDelete(attributes, "$type");
					StructDelete(attributes, "overwrite");
					var name = ListFirst(StructKeyList(attributes));
					var expression = arguments.task[name];
					instance = variables.context.createSetTask(name, expression, overwrite);
					break;
			}

			// check for subtasks
			if (StructKeyExists(arguments.task, "sub")) {
				for (var subtask in arguments.task.sub) {
					instance.addSubtask(createTask(subtask));
				}
			}
		}

		return instance;
	}

}