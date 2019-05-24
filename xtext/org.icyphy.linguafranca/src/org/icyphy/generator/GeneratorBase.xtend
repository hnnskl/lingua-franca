/*
 * Generator base class for shared code between code generators.
 */
package org.icyphy.generator

import java.text.NumberFormat
import java.text.ParseException
import java.util.HashMap
import java.util.HashSet
import java.util.Hashtable
import java.util.LinkedHashMap
import java.util.LinkedList
import org.eclipse.emf.ecore.EObject
import org.eclipse.xtext.nodemodel.util.NodeModelUtils
import org.icyphy.linguaFranca.Component
import org.icyphy.linguaFranca.Composite
import org.icyphy.linguaFranca.Connection
import org.icyphy.linguaFranca.Instance
import org.icyphy.linguaFranca.LinguaFrancaFactory
import org.icyphy.linguaFranca.Reaction
import org.icyphy.linguaFranca.Time

/**
 * Generator base class for shared code between code generators.
 * 
 * @author Edward A. Lee, Marten Lohstroh, Chris Gill
 */
class GeneratorBase {
	
	// Map from component (reactor or composite) to properties of the component.
	protected var componentToProperties = new HashMap<Component,ComponentProperties>()
	
	// Map from reactor or composite class name to the
	// component defining that class.
	var classToComponent = new LinkedHashMap<String,Component>()

	// All code goes into this string buffer.
	var code = new StringBuilder
	
	// Map from builder to its current indentation.
	var indentation = new HashMap<StringBuilder,String>()
	
	// The main (top-level) reactor instance.
	protected ReactorInstance main 
	
	// Map from time units to an expression that can convert a number in
	// the specified time unit into nanoseconds. This expression may need
	// to have a suffix like 'LL' or 'L' appended to it, depending on the
	// target language, to ensure that the result is a 64-bit long.
	static public var timeUnitsToNs = #{
			'nsec' -> 1L,
		 	'usec' -> 1000L,
			'msec'->1000000L,
			'sec'->1000000000L,
			'secs'->1000000000L,
			'minute'->60000000000L,
			'minutes'->60000000000L,
			'hour'->3600000000000L,
			'hours'->3600000000000L,
			'day'->86400000000000L,
			'days'->86400000000000L,
			'week'->604800000000000L, 
			'weeks'->604800000000000L}
	
	////////////////////////////////////////////
	//// Code generation functions to override for a concrete code generator.
	
	/** Collect data in a reactor or composite definition.
	 *  Subclasses should override this and be sure to call
	 *  super.generateComponent(component, importTable).
	 *  @param component The parsed component data structure.
	 *  @param importTable Substitution table for class names (from import statements).
	 */	
	def void generateComponent(Component component, Hashtable<String,String> importTable) {
				
		// Reset indentation, in case it has gotten messed up.
		indentation.put(code, "")
		
		classToComponent.put(component.componentBody.name, component)
		
		// Create the object for storing component properties.
		var properties = new ComponentProperties()
		componentToProperties.put(component, properties)

		// Record parameters.
		if (component.componentBody.parameters !== null) {
			for (param : component.componentBody.parameters.params) {
				properties.nameToParam.put(param.name, param)
			}
		}
		
		// Record inputs.
		for (input: component.componentBody.inputs) {
			properties.nameToInput.put(input.name, input)
		}
		
		// Record outputs.
		for (output: component.componentBody.outputs) {
			properties.nameToOutput.put(output.name, output)
		}
		
		// Record actions.
		for (action: component.componentBody.actions) {
			if (action.getDelay() === null) {
				action.setDelay("0")
			}
			properties.nameToAction.put(action.name, action)
		}
		
		// Record timers.
		for (timer: component.componentBody.timers) {
			properties.nameToTimer.put(timer.name, timer)
			var timing = timer.timing
			// Make sure every timing object has both an offset
			// and a period by inserting default of 0.
			var zeroTime = LinguaFrancaFactory.eINSTANCE.createTime()
			zeroTime.setTime("0")
			if (timing === null) {
				timing = LinguaFrancaFactory.eINSTANCE.createTiming()
				timing.setOffset(zeroTime)
				timing.setPeriod(zeroTime)
			} else if (timing.getPeriod === null) {
				timing.setPeriod(zeroTime)
			}
			
			properties.nameToTiming.put(timer.name, timing)
		}
		
		// Record the reactions triggered by each trigger.
		for (reaction: component.componentBody.reactions) {
			// Iterate over the reaction's triggers
			if (reaction.triggers !== null && reaction.triggers.length > 0) {
				for (trigger: reaction.triggers) {
					// Check validity of the trigger.
					if (properties.nameToInput.get(trigger) === null
							&& getTiming(component, trigger) === null
							&& getAction(component, trigger) === null) {
                        reportError(reaction,
                        		"Trigger '" + trigger + "' is neither an input, a timer, nor an action.")
                    }
                    var reactionList = properties.triggerNameToReactions.get(trigger)
                    if (reactionList === null) {
                    	reactionList = new LinkedList<Reaction>()
						properties.triggerNameToReactions.put(trigger, reactionList)
                    }
                    reactionList.add(reaction)
				}	
			}
		}
		if (component instanceof Composite) {
			// Record contained instances.
			for (instance: component.instances) {
				properties.nameToInstance.put(instance.name, instance)
			}
			// Record (and check) connections.
			for (connection: component.connections) {
				var split = connection.leftPort.split('\\.')
				if (split.length === 1) {
					// It is a local input port.
					if (getInput(component, connection.leftPort) === null) {
						reportError(connection,
								"Left side is not an input port of this composite: " + connection.leftPort)
					}
				} else if (split.length === 2) {
					// Form is reactorName.portName.
					var instance = properties.nameToInstance.get(split.get(0))
					if(instance === null) {
						reportError(connection,
								"No such instance: " + split.get(0))
					} else {
						var contained = getComponent(instance.reactorClass)
						// Contained object may be imported, i.e. not a Lingua Franca object.
						// Cannot check here.
						if (contained !== null) {
							var props = componentToProperties.get(contained)
							if(props.nameToOutput.get(split.get(1)) === null) {
								reportError(connection,
										"No such output port: " + connection.leftPort)
							}
						}
					}
				} else {
					reportError(connection, "Invalid port specification: " + connection.leftPort)
				}
				// Check the right port.
				split = connection.rightPort.split('\\.')
				if (split.length === 1) {
					// It is a local input port.
					if (getOutput(component, connection.rightPort) === null) {
						reportError(connection,
								"Right side is not an output port of this composite: " + connection.rightPort)
					}
				} else if (split.length === 2) {
					// Form is reactorName.portName.
					var instance = properties.nameToInstance.get(split.get(0))
					if(instance === null) {
						reportError(connection,
								"No such instance: " + split.get(0))
					} else {
						var contained = getComponent(instance.reactorClass)
						// Contained object may be imported, i.e. not a Lingua Franca object.
						// Cannot check here.
						if (contained !== null) {
							var props = componentToProperties.get(contained)
							if(props.nameToInput.get(split.get(1)) === null) {
								reportError(connection,
										"No such input port: " + connection.rightPort)
							}
						}
					}
				} else {
					reportError(connection, "Invalid port specification: " + connection.rightPort)
				}
				// Record the source-destination pair.
				var destinations = properties.outputNameToInputNames.get(connection.leftPort)
				if (destinations === null) {
					destinations = new HashSet<String>()
					properties.outputNameToInputNames.put(connection.leftPort, destinations)
				}
				destinations.add(connection.rightPort)
			}
			
			if (component.componentBody.name.equalsIgnoreCase("main")) {
				// Build the instance-specific structures.
				main = new ReactorInstance(component)
				generateContainedInstances(component, main, importTable)
			}
		}
	}
	
	/** For the given composite, create instances of each component (reactor or composite)
	 *  that it contains.
	 *  @param component The composite.
	 *  @param container The instance that is the container.
	 *  @param importTable The table of imports.
	 */
	def void generateContainedInstances(
		Composite component,
		ReactorInstance container,
		Hashtable<String,String> importTable
	) {
		// Generated instances
		for (instance: component.instances) {
			var contained = instantiate(instance, container, importTable)
			container.addContainedInstance(contained)
		}
		// Handle connections
		for (connection: component.connections) {
			connect(connection)
		}
	}
	
	/** Handle a connection
	 *  @param connection The connection.
	 */
	def connect(Connection connection) {
		// FIXME Generate code to initialize the input's "this" struct's
		// input field to point to the output's "this" struct's output
		// field. Do the same for _is_present fields.
	}
	
	/** Instantiate a reactor.
	 *  @param instance The instance declaration.
	 *  @param container The instance that is the container.
	 *  @param importTable Substitution table for class names (from import statements).
	 */
	def instantiate(
		Instance instance,
		ReactorInstance container,
		Hashtable<String,String> importTable
	) {
		var component = getComponent(instance.reactorClass)
		var reactorInstance = new ReactorInstance(component, instance, container)
		// Component may be imported, i.e. not a Lingua Franca component,
		// in which case, component === null.
		// If the component is a composite, then create instances of
		// whatever it instantiates.
		if (component instanceof Composite) {
			generateContainedInstances(component, reactorInstance, importTable)
		}
		reactorInstance
	}
	
	////////////////////////////////////////////
	//// Utility functions for generating code.
	
	/** Clear the buffer of generated code.
	 */
	protected def clearCode() {
		code = new StringBuilder
	}
	
	/** Return the Action with the given name.
	 *  @param component The Component.
	 *  @param name The name of the desired action.
	 *  @return The action, or null if there isn't one.
	 */
	protected def getAction(Component component, String name) {
		var properties = componentToProperties.get(component)
		properties.nameToAction.get(name)
	}
	
	/** Get the code produced so far.
	 *  @return The code produced so far as a String.
	 */
	protected def getCode() {
		code.toString()
	}
	
	/** Get the component defining a reactor or composite that has
	 *  the specified class name, or null if there is none.
	 *  @param className The component class name.
	 *  @return The component, or null if there isn't one matching the name.
	 */
	protected def getComponent(String className) {
		classToComponent.get(className)
	}
	
	/** Return the Input with the given name.
	 *  @param component The Component.
	 *  @param name The name of the desired input.
	 *  @return The input, or null if there isn't one.
	 */
	protected def getInput(Component component, String name) {
		var properties = componentToProperties.get(component)
		properties.nameToInput.get(name)
	}
	
	/** Return the Output with the given name.
	 *  @param component The Component.
	 *  @param name The name of the desired output.
	 *  @return The output, or null if there isn't one.
	 */
	protected def getOutput(Component component, String name) {
		var properties = componentToProperties.get(component)
		properties.nameToOutput.get(name)
	}
	
	/** Return the parameter with the given name.
	 *  @param component The Component.
	 *  @param name The name of the desired parameter.
	 *  @return The parameter, or null if there isn't one.
	 */
	protected def getParameter(Component component, String name) {
		var properties = componentToProperties.get(component)
		properties.nameToParam.get(name)
	}
	
	/** Return the parameters defined for the specified component.
	 *  @param component The component.
	 *  @return The parameters for the component.
	 */
	protected def getParameters(Component component) {
		var properties = componentToProperties.get(component)
		properties.nameToParam.values()
	}

	/** Get the list of reactions triggered by the specified trigger
	 *  for the specified component.
	 *  @param component The component.
	 *  @param name The name of the trigger (input, action, or timer).
	 *  @return A list of Reaction objects or null if there are none.
	 */
	protected def getReactions(Component component, String name) {
		var properties = componentToProperties.get(component)
		properties.triggerNameToReactions.get(name)
	}

	/** Return a set of timer names for a reactor class.
	 */
	protected def getTimerNames(Component component) {
		var properties = componentToProperties.get(component)
		properties.nameToTimer.keySet()
	}
	
	/** Get the timer with the specified name in the specified component.
	 *  @param component The component.
	 *  @param name The name of the timer.
	 *  @return A Timer object or null if there is no timer with the specified name.
	 */
	protected def getTimer(Component component, String name) {
		var properties = componentToProperties.get(component)
		properties.nameToTimer.get(name)
	}
	
	/** Get the timing of the timer with the specified name in the specified component.
	 *  @param component The component.
	 *  @param name The name of the timer.
	 *  @return A Timing object or null if there is no timer with the specified name.
	 */
	protected def getTiming(Component component, String name) {
		var properties = componentToProperties.get(component)
		properties.nameToTiming.get(name)
	}
	
	/** Get the map from triggers to the list of reactions
	 *  triggered by the trigger for the specified component.
	 *  @param component The component.
	 *  @return A map from triggers to the list of reactions triggered.
	 */
	protected def getTriggerToReactions(Component component) {
		var properties = componentToProperties.get(component)
		properties.triggerNameToReactions
	}
	
	/** Increase the indentation of the output code produced.
	 */
	protected def indent() {
		indent(code)
	}
	
	/** Increase the indentation of the output code produced
	 *  on the specified builder.
	 *  @param The builder to indent.
	 */
	protected def indent(StringBuilder builder) {
		var prefix = indentation.get(builder)
		if (prefix === null) {
			prefix = ""
		}
		val buffer = new StringBuffer(prefix)
		for (var i = 0; i < 4; i++) {
			buffer.append(' ');
		}
		indentation.put(builder, buffer.toString)
	}
	
	/** Append the specified text plus a final newline to the current
	 *  code buffer.
	 *  @param text The text to append.
	 */
	protected def pr(Object text) {
		pr(code, text)
	}
	
	/** Append the specified text plus a final newline to the specified
	 *  code buffer.
	 *  @param builder The code buffer.
	 *  @param text The text to append.
	 */
	protected def pr(StringBuilder builder, Object text) {
		// Handle multi-line text.
		var string = text.toString
		var indent = indentation.get(builder)
		if (indent === null) {
			indent = ""
		}
		if (string.contains("\n")) {
			// Replace all tabs with four spaces.
			string = string.replaceAll("\t", "    ")
			// Use two passes, first to find the minimum leading white space
			// in each line of the source text.
			var split = string.split("\n")
			var offset = Integer.MAX_VALUE
			var firstLine = true
			for (line : split) {
				// Skip the first line, which has white space stripped.
				if (firstLine) {
					firstLine = false
				} else {
					var numLeadingSpaces = line.indexOf(line.trim());
					if (numLeadingSpaces < offset) {
						offset = numLeadingSpaces
					}
				}
			}
			// Now make a pass for each line, replacing the offset leading
			// spaces with the current indentation.
			firstLine = true
			for (line : split) {
				builder.append(indent)
				// Do not trim the first line
				if (firstLine) {
					builder.append(line)
					firstLine = false
				} else {
					builder.append(line.substring(offset))
				}
				builder.append("\n")
			}
		} else {
			builder.append(indent)
			builder.append(text)
			builder.append("\n")
		}
	}
	
	/** If the argument starts with '{=', then remove it and the last two characters.
	 *  @return The body without the code delimiter or the unmodified argument if it
	 *   is not delimited.
	 */
	protected def String removeCodeDelimiter(String code) {
		if (code === null) {
			""
		} else if (code.startsWith("{=")) {
            code.substring(2, code.length - 2).trim();
        } else {
        	code
        }
	}
	
	/** Report an error on the specified parse tree object.
	 *  @param object The parse tree object.
	 *  @param message The error message.
	 */
	protected def reportError(EObject object, String message) {
		// FIXME: All calls to this should also be checked by the validator (See LinguaFrancaValidator.xtend).
        // In case we are using a command-line tool, we report the line number.
        // The caller should not throw an exception so compilation can continue.
        var node = NodeModelUtils.getNode(object)
        System.err.println("Line "
            		+ node.getStartLine()
               		+ ": "
            		+ message)
        // Return a string that can be inserted into the generated code.
        "[[ERROR: " + message + "]]"
	}

	/** Reduce the indentation by one level for generated code
	 *  in the default code buffer.
	 */
	protected def unindent() {
		unindent(code)
	}
	
	/** Reduce the indentation by one level for generated code
	 *  in the specified code buffer.
	 */
	protected def unindent(StringBuilder builder) {
		var indent = indentation.get(builder)
		if (indent !== null) {
			val end = indent.length - 4;
			if (end < 0) {
				indent = ""
			} else {
				indent = indent.substring(0, end)
			}
			indentation.put(builder, indent)
		}
	}
	
	/** Given a representation of time that may possibly include units,
	 *  return a string for the same amount of time
	 *  in terms of the specified baseUnit. If the two units are the
	 *  same, or if no time unit is given, return the number unmodified.
	 *  @param time The source time.
	 *  @param baseUnit The target unit.
	 */
	protected def unitAdjustment(Time time, String baseUnit) {
		if (time === null || time.time === null) {
			return '0'
		}
		if (time.unit === null || baseUnit.equals(time.unit)) {
			return time.time
		}
		try {
			var nf = NumberFormat.getInstance();
			// The following will try to return a Long, and if that fails, will return a Double.
			var parsed = nf.parse(time.time)
			var unitScale = timeUnitsToNs.get(time.unit)
			if (unitScale === null) {
				// Invalid unit specification.
				return reportError(time, "Invalid unit '" + time.unit + "'. Should be one of: " + timeUnitsToNs.keySet)
			}
			var baseScale = timeUnitsToNs.get(baseUnit)
			if (baseScale === null) {
				// This is an error in the target code generator, not in the source code.
				throw new Exception("Invalid target base unit: " + baseUnit + ". Should be one of: " + timeUnitsToNs.keySet)				
			}
			// Handle Double and Long separately.
			if (parsed instanceof Long) {
				// First convert the number to units of nanoseconds.
				var numberInNs = parsed.longValue() * unitScale
				// Then convert to baseUnits.
				var result = numberInNs / baseScale
				return result.toString()
			} else {
				// Assume its is a Double.
				// First convert the number to units of nanoseconds.
				var numberInNs = parsed.doubleValue() * unitScale
				// Then convert to baseUnits.
				var result = numberInNs / baseScale
				return result.toString()
			}
		} catch (ParseException ex) {
			return reportError(time, "Failed to parse number '" + time.time + "'. " + ex)
		}
	}
}
