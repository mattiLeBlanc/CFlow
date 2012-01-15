component Context accessors="true" {

	property name="debug" type="boolean" default="false";
	property name="implicitEvents" type="boolean" default="false";
	property name="defaultTarget" type="string" default="";
	property name="defaultEvent" type="string" default="";
	property name="controllerMapping" type="string" default="";
	property name="viewMapping" type="string" default="";
	property name="configurationPath" type="string" default="";

	variables.controllers = {}; // controllers are static, so we need only one instance of each
	variables.tasks = {
		event = {},
		start = {},
		end = {},
		before = {},
		after = {}
	};

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

		return handleEvent(targetName, eventType, properties);
	}

	/**
	 * Fires an event on the given target.
	 **/
	public Response function handleEvent(required string targetName, required string eventType, struct properties = {}) {

		var response = new Response();
		var event = new Event(arguments.targetName, arguments.eventType, arguments.properties);

		var success = getStartTask(event).process(event, response);

		if (success) {
			success = dispatchEvent(event, response);
		}

		if (!success) {
			// for the remainder, we need an event object with its canceled flag reset
			event = event.clone();
		}

		getEndTask(event).process(event, response);

		return response;
	}

	public boolean function dispatchEvent(required Event event, required Response response) {

		var success = getBeforeTask(arguments.event).process(arguments.event, arguments.response);

		if (success) {
			success = getEventTask(arguments.event).process(arguments.event, arguments.response)
		}

		if (success) {
			success = getAfterTask(arguments.event).process(arguments.event, arguments.response);
		}

		return success;
	}

	public void function register(required Task task, required string phase, required string targetName, string eventType) {

		switch (arguments.phase) {
			case "start":
			case "end":
			case "before":
			case "after":
				variables.tasks[arguments.phase][arguments.targetName] = arguments.task;
				break;
			default:
				if (!StructKeyExists(arguments, "eventType")) {
					throw(type="cflow", message="Event type is required when registering tasks for the event phase");
				}
				if (!StructKeyExists(variables.tasks, arguments.targetName)) {
					variables.tasks[arguments.targetName] = {};
				}
				variables.tasks[arguments.targetName][arguments.eventType] = arguments.task;
				break;
		}

	}

	public Renderer function getRenderer() {

		if (!StructKeyExists(variables, "renderer")) {
			setRenderer(new CFMLRenderer());
		}

		return variables.renderer;
	}

	public void function setRenderer(required Renderer renderer) {
		variables.renderer = arguments.renderer;
	}

	/**
	 * Returns the task for the given event.
	 **/
	private Task function getEventTask(required event Event) {

		var task = JavaCast("null", 0);
		// check if there are tasks for this event
		var targetName = arguments.event.getTarget();
		var eventType = arguments.event.getType();
		if (StructKeyExists(variables.tasks.event, targetName) && StructKeyExists(variables.tasks.event[targetName], eventType)) {
			task = variables.tasks.event[targetName][eventType];
		} else {
			task = new EventTask();
			if (getImplicitEvents()) {
				// we now assume there is a controller with the name of the target, that exposes a method with the name of the event type
				task.addSubtask(createInvokeTask(targetName, eventType));
				// and that there is a template in a directory with the name of the target, that has the same name as the event type
				task.addSubtask(createRenderTask(targetName & "/" & eventType));
			}
		}

		return task;
	}

	private Task function getPhaseTask(required string phase, required Event event) {

		var task = JavaCast("null", 0);
		var targetName = arguments.event.getTarget();

		if (StructKeyExists(variables.tasks[arguments.phase], targetName)) {
			task = variables.tasks[arguments.phase][targetName];
		} else {
			// create an empty EventTask
			task = new EventTask();
		}

		return task;
	}

	private Task function getStartTask(required Event event) {
		return getPhaseTask("start", arguments.event);
	}

	private Task function getEndTask(required Event event) {
		return getPhaseTask("end", arguments.event);
	}

	private Task function getBeforeTask(required Event event) {
		return getPhaseTask("before", arguments.event);
	}

	private Task function getAfterTask(required Event event) {
		return getPhaseTask("after", arguments.event);
	}

	private component function getController(required string name) {

		if (!StructKeyExists(variables.controllers, arguments.name)) {
			variables.controllers[arguments.name] = new "#getControllerMapping()#.#arguments.name#"(this);
		}

		return variables.controllers[arguments.name];
	}

	public InvokeTask function createInvokeTask(required string controllerName, required string methodName) {
		return new InvokeTask(getController(arguments.controllerName), arguments.methodName);
	}

	public DispatchTask function createDispatchTask(required string targetName, required string eventType) {
		return new DispatchTask(this, arguments.targetName, arguments.eventType);
	}

	public RenderTask function createRenderTask(required string template) {
		return new RenderTask(getRenderer(), arguments.template);
	}

}