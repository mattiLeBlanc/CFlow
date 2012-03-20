component Result {

	variables.messages = collection(); // we use an argument collection, because it keeps the order of the keys that are added
	variables.passed = true;

	public void function addMessages(required string name, required array messages) {

		variables.messages[arguments.name] = arguments.messages;
		if (!ArrayIsEmpty(arguments.messages)) {
			variables.passed = false;
		}

	}

	public boolean function isPassed(string name) {

		var passed = variables.passed;
		if (StructKeyExists(arguments, "name")) {
			// the rules must have been tested (so the struct key exists), and must have resulted in 0 messages
			passed = StructKeyExists(variables.messages, arguments.name) && ArrayIsEmpty(variables.messages[arguments.name]);
		}

		return passed;
	}

	public array function getNames() {
		return StructKeyArray(variables.messages);
	}

	public array function getMessages(required string name) {

		var messages = JavaCast("null", 0);
		if (StructKeyExists(variables.messages, arguments.name)) {
			messages = variables.messages[arguments.name];
		} else {
			messages = [];
		}

		return messages;
	}

	private array function collection() {
		return arguments;
	}

}