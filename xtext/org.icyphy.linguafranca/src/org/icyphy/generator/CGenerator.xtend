/* Generator for C target. */

/*************
Copyright (c) 2019, The University of California at Berkeley.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
***************/

package org.icyphy.generator

import java.io.File
import java.io.FileOutputStream
import java.math.BigInteger
import java.util.ArrayList
import java.util.Collection
import java.util.HashMap
import java.util.HashSet
import java.util.LinkedList
import java.util.regex.Pattern
import org.eclipse.emf.common.util.URI
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.emf.ecore.resource.ResourceSet
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext
import org.eclipse.xtext.nodemodel.util.NodeModelUtils
import org.icyphy.ASTUtils
import org.icyphy.InferredType
import org.icyphy.TimeValue
import org.icyphy.linguaFranca.Action
import org.icyphy.linguaFranca.ActionOrigin
import org.icyphy.linguaFranca.Code
import org.icyphy.linguaFranca.Import
import org.icyphy.linguaFranca.Input
import org.icyphy.linguaFranca.Instantiation
import org.icyphy.linguaFranca.LinguaFrancaFactory
import org.icyphy.linguaFranca.LinguaFrancaPackage
import org.icyphy.linguaFranca.Output
import org.icyphy.linguaFranca.Parameter
import org.icyphy.linguaFranca.Port
import org.icyphy.linguaFranca.Reaction
import org.icyphy.linguaFranca.Reactor
import org.icyphy.linguaFranca.StateVar
import org.icyphy.linguaFranca.TimeUnit
import org.icyphy.linguaFranca.Timer
import org.icyphy.linguaFranca.TriggerRef
import org.icyphy.linguaFranca.VarRef
import org.icyphy.linguaFranca.Variable

import static extension org.icyphy.ASTUtils.*

/** 
 * Generator for C target.
 * 
 * ## Self Struct
 * 
 * For each reactor class, this generator defines a "self" struct with fields
 * for each of the following:
 * 
 * * parameter: the field name and type match the parameter.
 * * state: the field name and type match the state.
 * * output: the field name prepends the output name with "__".
 * * output present: boolean indicating whether the output is present.
 * * output number of destinations: integer indicating how many destinations there are (for reference counting).
 * * input: a pointer to the source value of this input (in another self struct).
 * * input present: a pointer to the source's boolean indicating whether the value is present.
 * 
 * If, in addition, the reactor contains other reactors and reacts to their outputs,
 * then there will be a struct within the self struct for each such contained reactor.
 * The name of that self struct will be the name of the contained reactor prepended with "__".
 * That inside struct will contain pointers the outputs of the contained reactors
 * that are read together with pointers to booleans indicating whether those outputs are present.
 * 
 * If, in addition, the reactor has a reaction to shutdown, then there will be a pointer to
 * trigger_t object (see reactor.h) for the shutdown event.
 * 
 * ## Reaction Functions
 * 
 * For each reaction in a reactor class, this generator will produce a C function
 * that expects a pointer to an instance of the "self" struct as an argument.
 * This function will contain verbatim the C code specified in the reaction, but
 * before that C code, the generator inserts a few lines of code that extract from the
 * self struct the variables that that code has declared it will use. For example, if
 * the reaction declares that it is triggered by or uses an input named "x" of type
 * int, the function will contain code like this:
 * ```
 *     bool x_is_present = *(self->__x_is_present);
 *     int x;
 *     if (x_is_present) {
 *         x = *(self->__x);
 *     }
 * ```
 * If the programmer fails to declare that it uses x, then the absence of the
 * above code will trigger a compile error when the verbatim code attempts to read x.
 * 
 * If, in addition, the reactor has a reaction to shutdown, then there will be a pointer to
 * trigger_t object (see reactor.h) for the shutdown event. This will be used to define the
 * following variables in the reaction function:
 * 
 * * shutdown_is_present: A boolean indicating whether a shutdown is in progress.
 * * shutdown_has_value: A boolean indicating whether the shutdown action has a value.
 * * shutdown_token: Pointer to the token_t object containing the shutdown value, if any.
 *
 * ## Constructor
 * 
 * For each reactor class, this generator will create a constructor function named
 * new_R, where R is the reactor class name. This function will malloc and return
 * a pointer to an instance of the "self" struct.  This struct initially represents
 * an unconnected reactor. To establish connections between reactors, additional
 * information needs to be inserted (see below). The self struct is made visible
 * to the body of a reaction as a variable named "self".  The self struct contains the
 * following:
 * 
 * * Parameters: For each parameter p of the reactor, there will be a field p
 *   with the type and value of the parameter. So C code in the body of a reaction
 *   can access parameter values as self->p.
 * 
 * * State variables: For each state variable s of the reactor, there will be a field s
 *   with the type and value of the state variable. So C code in the body of a reaction
 *   can access state variables as as self->s.
 * 
 * The self struct also contains various fields that the user is not intended to
 * use. The names of these fields begin with at least two underscores. They are:
 * 
 * * Outputs: For each output named "out", there will be a field "__out" whose
 *   type matches that of the output. The output value is stored here. There is
 *   also a field "__out_is_present" that is a boolean indicating whether the
 *   output has been set. This field is reset to false at the start of every time
 *   step. There is also a field "__out_num_destinations" whose value matches the
 *   number of downstream reactions that use this variable. This field must be
 *   set when connections are made or changed. It is used to initialize
 *   reference counts for dynamically allocated message payloads.
 * 
 * * Inputs: For each input named "in" of type T, there is a field named "__in"
 *   of type T*. This field contains a pointer to the source of data for this
 *   input. There is also a field "__in_is_present" of type bool* that points
 *   to a boolean that indicates whether the input is present.
 * 
 * * Outputs of contained reactors: If a reactor reacts to outputs of a
 *   contained reactor R, then the self struct will contain a nested struct
 *   named "__R" that has fields pointing to those outputs. For example,
 *   if R has an output "out" of type T, then there will be field in __R
 *   named "__out" of type T* and a field named "__out_is_present" of type
 *   bool*.
 * 
 * * Inputs of contained reactors: If a reactor sends to inputs of a
 *   contained reactor R, then the self struct will contain a nested struct
 *   named "__R" that has fields for storing the values provided to those
 *   inputs. For example, if R has an input "in" of type T, then there will
 *   be field in __R named "__in" of type T and a field named "__in_is_present"
 *   of type bool.
 * 
 * * Actions: If the reactor has an action a (logical or physical), then there
 *   will be a field in the self struct named "__a" of type trigger_t.
 *   That struct contains various things, including an array of reactions
 *   sensitive to this trigger and a token_t struct containing the value of
 *   the action, if it has a value.  See reactor.h in the C library for
 *   details.
 * 
 * * Reactions: Each reaction will have several fields in the self struct.
 *   Each of these has a name that begins with "___reaction_i", where i is
 *   the number of the reaction, starting with 0. The fields are:
 *   * ___reaction_i: The struct that is put onto the reaction queue to
 *     execute the reaction (see reactor.h in the C library).
 *   * ___reaction_i_outputs_are_present: An array of pointers to the
 *     __out_is_present fields of each output "out" that may be set by
 *     this reaction. This array also includes pointers to the _is_present
 *     fields of inputs of contained reactors to which this reaction writes.
 *     This array is set up by the constructor.
 *   * ___reaction_i_num_outputs: The size of the previous array.
 *   * ___reaction_i_triggers: This is an array of arrays of pointers
 *     to trigger_t structs. The first level array has one entry for
 *     each effect of the reaction that is a port (actions are ignored).
 *     Each such entry is an array containing pointers to trigger structs for
 *     downstream inputs.
 *   * ___reaction_i_triggered_sizes: An array indicating the size of
 *     each array in ___reaction_i_triggers. The size of this array is
 *     the number of ports that are effects of this reaction.
 * 
 *  * Timers: For each timer t, there is are two fields in the self struct:
 *    * ___t_trigger: The trigger_t struct for this timer (see reactor.h).
 *    * ___t_trigger_reactions: An array of reactions (pointers to the
 *      reaction_t structs on this self struct) sensitive to this timer.
 *
 * * Triggers: For each Timer, Action, Input, and Output of a contained
 *   reactor that triggers reactions, there will be a trigger_t struct
 *   on the self struct with name "___t", where t is the name of the trigger.
 * 
 * ## Connections Between Reactors
 * 
 * Establishing connections between reactors involves two steps.
 * First, each destination (e.g. an input port) must have pointers to
 * the source (the output port). As explained above, for an input named
 * "in", the field "__in" is a pointer to the output data being read.
 * In addition, "__in_is_present" is a pointer to the corresponding
 * out_is_present field of the output reactor's self struct.
 *  
 * In addition reaction_i struct on the self struct has a triggers
 * field that records all the trigger_t structs for ports and reactions
 * that are triggered by the i-th reaction. The triggers field is
 * an array of arrays of pointers to trigger_t structs.
 * The length of the outer array is the number of output ports the
 * reaction effects plus the number of input ports of contained
 * reactors that it effects. Each inner array has a length equal to the
 * number final destinations of that output port or input port.
 * The reaction_i struct has an array triggered_sizes that indicates
 * the sizes of these inner arrays. The num_outputs field of the
 * reaction_i struct gives the length of the triggered_sizes and
 * (outer) triggers arrays.
 * 
 * ## Runtime Tables
 * 
 * This generator creates an populates the following tables used at run time.
 * These tables may have to be resized and adjusted when mutations occur.
 * 
 * * __is_present_fields: An array of pointers to booleans indicating whether an
 *   event is present. The __start_time_step() function in reactor_common.c uses
 *   this to mark every event absent at the start of a time step. The size of this
 *   table is contained in the variable __is_present_fields_size.
 * 
 * * __tokens_with_ref_count: An array of pointers to structs that point to token_t
 *   objects, which carry non-primitive data types between reactors. This is used
 *   by the __start_time_step() function to decrement reference counts, if necessary,
 *   at the conclusion of a time step. Then the reference count reaches zero, the
 *   memory allocated for the token_t object will be freed.  The size of this
 *   array is stored in the __tokens_with_ref_count_size variable.
 * 
 * * __timer_triggers: An array of pointers to trigger_t structs for timers that
 *   need to be started when the program runs. The length of this table is in the
 *   __timer_triggers_size variable.
 * 
 * * __action_table: For a federated execution, each federate will have this table
 *   that maps port IDs to the corresponding trigger_t struct.
 * 
 * @author{Edward A. Lee <eal@berkeley.edu>}
 * @author{Marten Lohstroh <marten@berkeley.edu>}
 * @author{Mehrdad Niknami <mniknami@berkeley.edu>}
 * @author{Chris Gill, <cdgill@wustl.edu>}
 * @author {Christian Menard <christian.menard@tu-dresden.de>
 */
class CGenerator extends GeneratorBase {
    
    ////////////////////////////////////////////
    //// Private variables
    
    // Set of acceptable import targets includes only C.
    val acceptableTargetSet = newHashSet('C')
    
    // Additional sources to add to the compile command if appropriate.
    var compileAdditionalSources = null as ArrayList<String>

    // Additional libraries to add to the compile command using the "-l" command-line option.
    var compileLibraries = null as ArrayList<String>

    // List of deferred assignments to perform in initialize_trigger_objects.
    // FIXME: Remove this and InitializeRemoteTriggersTable
    var deferredInitialize = new LinkedList<InitializeRemoteTriggersTable>()
    
    // Place to collect code to initialize the trigger objects for all reactor instances.
    var initializeTriggerObjects = new StringBuilder()

    // Place to collect code to go at the end of the __initialize_trigger_objects() function.
    var initializeTriggerObjectsEnd = new StringBuilder()

    /** The main (top-level) reactor instance. */
    protected ReactorInstance main
    
    // The command to run the generated code if specified in the target directive.
    var runCommand = new ArrayList<String>()

    // Place to collect shutdown action instances.
    var shutdownActionInstances = new LinkedList<ActionInstance>()

    // Place to collect code to execute at the start of a time step.
    var startTimeStep = new StringBuilder()
    
    /** Count of the number of _is_present fields of the self struct that
     *  need to be reinitialized in __start_time_step().
     */
    var startTimeStepIsPresentCount = 0
    
    /** Count of the number of token pointers that need to have their
     *  reference count decremented in __start_time_step().
     */
    var startTimeStepTokens = 0

    // Place to collect code to initialize timers for all reactors.
    var startTimers = new StringBuilder()
    var startTimersCount = 0

    // For each reactor, we collect a set of input and parameter names.
    var triggerCount = 0


    new () {
        super()
        // set defaults
        this.targetCompiler = "gcc"
        this.targetCompilerFlags = "-O2"// -Wall -Wconversion"
    }

    ////////////////////////////////////////////
    //// Public methods

    /** Generate C code from the Lingua Franca model contained by the
     *  specified resource. This is the main entry point for code
     *  generation.
     *  @param resource The resource containing the source code.
     *  @param fsa The file system access (used to write the result).
     *  @param context FIXME: Undocumented argument. No idea what this is.
     */
    override void doGenerate(Resource resource, IFileSystemAccess2 fsa,
            IGeneratorContext context) {
        
        // The following generates code needed by all the reactors.
        super.doGenerate(resource, fsa, context)
        
        // Generate code for each reactor. 
        for (r : reactors) {
            r.generateReactorFederated(null)
        }
        
        // Create the output directories if they don't yet exist.
        var srcGenPath = directory + File.separator + "src-gen"
        var outPath = directory + File.separator + "bin"
        var dir = new File(srcGenPath)
        if (!dir.exists()) dir.mkdirs()
        dir = new File(outPath)
        if (!dir.exists()) dir.mkdirs()

        // Copy the required library files into the target file system.
        // This will overwrite previous versions.
        var files = newArrayList("reactor_common.c", "reactor.h", "pqueue.c", "pqueue.h", "util.h", "util.c")
        if (targetThreads === 0) {
            files.add("reactor.c")
        } else {
            files.add("reactor_threaded.c")
        }
        // If there are federates, copy the required files for that.
        // Also, create two RTI C files, one that launches the federates
        // and one that does not.
        if (federates.length > 1) {
            files.addAll("rti.c", "rti.h", "federate.c")
            createFederateRTI()
            createLauncher()
        }
        
        for (file : files) {
            copyFileFromClassPath(
                "/" + "lib" + "/" + "core" + "/" + file,
                srcGenPath + File.separator + "core" +  File.separator + file
            )
        }


        // Target-specific files
        var target_files = newArrayList("ctarget.h");

        for (file : target_files) {
            copyFileFromClassPath(
                "/" + "lib" + "/" + "C" + "/" + file,
                srcGenPath + File.separator + file
            )
        }

        // Perform distinct code generation into distinct files for each federate.
        val baseFilename = filename
        
        var commonCode = code;
        var commonStartTimers = startTimers;
        for (federate : federates) {
            deferredInitialize.clear()
            shutdownActionInstances.clear()
            startTimeStepIsPresentCount = 0
            startTimeStepTokens = 0
            
            // Only generate one output if there is no federation.
            if (!federate.isSingleton) {
                filename = baseFilename + '_' + federate.name
                // Clear out previously generated code.
                code = new StringBuilder(commonCode)
                initializeTriggerObjects = new StringBuilder()
                initializeTriggerObjectsEnd = new StringBuilder()
                
                startTimeStep = new StringBuilder()
                startTimers = new StringBuilder(commonStartTimers)
                // This should go first in the start_timers function.
                pr(startTimers, 'synchronize_with_other_federates('
                    + federate.id
                    + ', "'
                    + federationRTIProperties.get('host') 
                    + '", ' + federationRTIProperties.get('port')
                    + ");"
                )
            }
        
            // Build the instantiation tree if a main reactor is present.
            if (this.mainDef !== null) {
                generateReactorFederated(this.mainDef.reactorClass, federate)
                if (this.main === null) {
                    // Recursively build instances. This is done once because
                    // it is the same for all federates.
                    this.main = new ReactorInstance(mainDef, null, this) 
                }   
            }
        
            // Derive target filename from the .lf filename.
            val cFilename = filename + ".c";

            // Delete source previously produced by the LF compiler.
            var file = new File(srcGenPath + File.separator + cFilename)
            if (file.exists) {
                file.delete
            }

            // Delete binary previously produced by the C compiler.
            file = new File(outPath + File.separator + filename)
            if (file.exists) {
                file.delete
            }

            // Generate main instance, if there is one.
            // Note that any main reactors in imported files are ignored.        
            if (this.main !== null) {
                generateReactorInstance(this.main, federate)

                // Generate function to set default command-line options.
                // A literal array needs to be given outside any function definition,
                // so start with that.
                if (runCommand.length > 0) {
                    pr('char* __default_argv[] = {"' + runCommand.join('", "') + '"};')
                }
                pr('void __set_default_command_line_options() {\n')
                indent()
                if (runCommand.length > 0) {
                    pr('default_argc = ' + runCommand.length + ';')
                    pr('default_argv = __default_argv;')
                }
                unindent()
                pr('}\n')
                
                // If there are timers, create a table of timers to be initialized.
                if (startTimersCount > 0) {
                    pr('''
                        // Array of pointers to timer triggers to start the timers in __start_timers().
                        trigger_t* __timer_triggers[«startTimersCount»];
                        int __timer_triggers_size = «startTimersCount»;
                    ''')
                }
                
                // Generate function to return a pointer to the action trigger_t
                // that handles incoming network messages destined to the specified
                // port. This will only be used if there are federates.
                if (federate.networkMessageActions.size > 0) {
                    pr('''trigger_t* __action_table[«federate.networkMessageActions.size»];''')
                }
                pr('trigger_t* __action_for_port(int port_id) {\n')
                indent()
                if (federate.networkMessageActions.size > 0) {
                    // Create a static array of trigger_t pointers.
                    // networkMessageActions is a list of Actions, but we
                    // need a list of trigger struct names for ActionInstances.
                    // There should be exactly one ActionInstance in the
                    // main reactor for each Action.
                    val triggers = new LinkedList<String>()
                    for (action : federate.networkMessageActions) {
                        // Find the corresponding ActionInstance.
                        val actionInstance = main.getActionInstance(action)
                        triggers.add(triggerStructName(actionInstance))
                    }
                    var actionTableCount = 0
                    for (trigger : triggers) {
                        pr(initializeTriggerObjects, '''
                            __action_table[«actionTableCount++»] = &«trigger»;
                        ''')
                    }
                    pr('''
                        if (port_id < «federate.networkMessageActions.size») {
                            return __action_table[port_id];
                        } else {
                            return NULL;
                        }
                    ''')
                } else {
                    pr('return NULL;')
                }
                unindent()
                pr('}\n')
                
                // Generate function to initialize the trigger objects for all reactors.
                pr('void __initialize_trigger_objects() {\n')
                indent()
                
                // Create the table used to decrement reference counts between time steps.
                if (startTimeStepTokens > 0) {
                    // Allocate the initial (before mutations) array of pointers to tokens.
                    pr('''
                        __tokens_with_ref_count_size = «startTimeStepTokens»;
                        __tokens_with_ref_count = (token_present_t*)malloc(«startTimeStepTokens» * sizeof(token_present_t));
                    ''')
                }
                // Create the table to initialize _is_present fields to false between time steps.
                if (startTimeStepIsPresentCount > 0) {
                    // Allocate the initial (before mutations) array of pointers to _is_present fields.
                    pr('''
                        // Create the array that will contain pointers to _is_present fields to reset on each step.
                        __is_present_fields_size = «startTimeStepIsPresentCount»;
                        __is_present_fields = (bool**)malloc(«startTimeStepIsPresentCount» * sizeof(bool*));
                    ''')
                }
                pr(initializeTriggerObjects.toString)
                pr('// Populate arrays of trigger pointers.')
                pr(initializeTriggerObjectsEnd.toString)
                doDeferredInitialize(federate)
                
                // Put the code here to set up the tables that drive resetting is_present and
                // decrementing reference counts between time steps. This code has to appear
                // in __initialize_trigger_objects() after the code that makes connections
                // between inputs and outputs.
                pr(startTimeStep.toString)
                
                setReactionPriorities(main, federate)
                if (federates.length > 1) {
                    if (federate.dependsOn.size > 0) {
                        pr('__fed_has_upstream  = true;')
                    }
                    if (federate.sendsTo.size > 0) {
                        pr('__fed_has_downstream = true;')
                    }
                }
                unindent()
                pr('}\n')

                // Generate function to start timers for all reactors.
                pr("void __start_timers() {")
                indent()
                pr(startTimers.toString)
                if (startTimersCount > 0) {
                    pr('''
                       for (int i = 0; i < __timer_triggers_size; i++) {
                           __schedule(__timer_triggers[i], 0LL, NULL);
                       }
                    ''')
                }
                unindent()
                pr("}")

                // Generate a function that will either do nothing
                // (if there is only one federate) or, if there are
                // downstream federates, will notify the RTI
                // that the specified logical time is complete.
                pr('''
                    void logical_time_complete(instant_t time) {
                        «IF federates.length > 1»
                            __logical_time_complete(time);
                        «ENDIF»
                    }
                ''')
                
                // Generate a function that will either just return immediately
                // if there is only one federate or will notify the RTI,
                // if necessary, of the next event time.
                pr('''
                    instant_t next_event_time(instant_t time) {
                        «IF federates.length > 1»
                            return __next_event_time(time);
                        «ELSE»
                            return time;
                        «ENDIF»
                    }
                ''')
                
                // Generate function to schedule shutdown actions if any
                // reactors have reactions to shutdown.
                pr('bool __wrapup() {\n')
                indent()
                pr('__start_time_step();   // To free memory allocated for actions.')
                for (instance : shutdownActionInstances) {
                    pr('__schedule(&' + triggerStructName(instance) + ', 0LL, NULL);')
                }
                if (shutdownActionInstances.length === 0) {
                    pr('return false;')
                } else {
                    pr('return true;')
                }
                unindent()
                pr('}\n')
                
                // Generate the termination function.
                // If there are federates, this will resign from the federation.
                if (federates.length > 1) {
                    pr('''
                        void __termination() {
                            unsigned char message_marker = RESIGN;
                            write(rti_socket, &message_marker, 1);
                        }
                    ''')
                } else {
                    pr("void __termination() {}");
                }
            }

            // Write the generated code to the output file.
            var fOut = new FileOutputStream(
                new File(srcGenPath + File.separator + cFilename));
            fOut.write(getCode().getBytes())
            fOut.close()
        }
        // Restore the base filename.
        filename = baseFilename
        
        // In case we are in Eclipse, make sure the generated code is visible.
        refreshProject()
        
        if (!targetNoCompile) {
            compileCode()
        } else {
            println("Exiting before invoking target compiler.")
        }
    }
    
    /** Invoke the compiler on the generated code. */
    def compileCode() {

        // If there is more than one federate, compile each one.
        var fileToCompile = filename // base file name.
        for (federate : federates) {
            // Empty string means no federates were defined, so we only
            // compile one file.
            if (!federate.isSingleton) {
                fileToCompile = filename + '_' + federate.name
            }
            executeCommand(compileCommand(fileToCompile), directory)
        }
        // Also compile the RTI files if there is more than one federate.
        if (federates.length > 1) {
            fileToCompile = filename + '_RTI'
            executeCommand(compileCommand(fileToCompile), directory)
        }
    }

    // //////////////////////////////////////////
    // // Code generators.
        
    /** Create the runtime infrastructure (RTI) source file.
     */
    def createFederateRTI() {
        // Derive target filename from the .lf filename.
        var cFilename = filename + "_RTI.c"
        
        var srcGenPath = directory + File.separator + "src-gen"
        var outPath = directory + File.separator + "bin"

        // Delete source previously produced by the LF compiler.
        var file = new File(srcGenPath + File.separator + cFilename)
        if (file.exists) {
            file.delete
        }

        // Delete binary previously produced by the C compiler.
        file = new File(outPath + File.separator + filename)
        if (file.exists) {
            file.delete
        }
        
        val rtiCode = new StringBuilder()
        pr(rtiCode, '''
            #ifdef NUMBER_OF_FEDERATES
            #undefine NUMBER_OF_FEDERATES
            #endif
            #define NUMBER_OF_FEDERATES «federates.length»
            #include "core/rti.c"
            int main(int argc, char* argv[]) {
        ''')
        indent(rtiCode)
        
        // Initialize the array of information that the RTI has about the
        // federates.
        // FIXME: No support below for some federates to be FAST and some REALTIME.
        pr(rtiCode, '''
            for (int i = 0; i < NUMBER_OF_FEDERATES; i++) {
                initialize_federate(i);
                «IF targetFast»
                    federates[i].mode = FAST;
                «ENDIF»
            }
        ''')
        // Initialize the arrays indicating connectivity to upstream and downstream federates.
        for(federate : federates) {
            if (!federate.dependsOn.keySet.isEmpty) {
                // Federate receives non-physical messages from other federates.
                // Initialize the upstream and upstream_delay arrays.
                val numUpstream = federate.dependsOn.keySet.size
                // Allocate memory for the arrays storing the connectivity information.
                pr(rtiCode, '''
                    federates[«federate.id»].upstream = (int*)malloc(sizeof(federate_t*) * «numUpstream»);
                    federates[«federate.id»].upstream_delay = (interval_t*)malloc(sizeof(interval_t*) * «numUpstream»);
                    federates[«federate.id»].num_upstream = «numUpstream»;
                ''')
                // Next, populate these arrays.
                // Find the minimum delay in the process.
                // FIXME: Zero delay is not really the same as a microstep delay.
                var count = 0;
                for (upstreamFederate : federate.dependsOn.keySet) {
                    pr(rtiCode, '''
                        federates[«federate.id»].upstream[«count»] = «upstreamFederate.id»;
                        federates[«federate.id»].upstream_delay[«count»] = 0LL;
                    ''')
                    // The minimum delay calculation needs to be made in the C code because it
                    // may depend on parameter values.
                    // FIXME: These would have to be top-level parameters, which don't really
                    // have any support yet. Ideally, they could be overridden on the command line.
                    // When that is done, they will need to be in scope here.
                    val delays = federate.dependsOn.get(upstreamFederate)
                    if (delays !== null) {
                        for (value : delays) {
                            pr(rtiCode, '''
                                if (federates[«federate.id»].upstream_delay[«count»] < «value.getTargetTime») {
                                    federates[«federate.id»].upstream_delay[«count»] = «value.getTargetTime»;
                                }
                            ''')
                        }
                    }
                    count++;
                }
            }
            // Next, set up the downstream array.
            if (!federate.sendsTo.keySet.isEmpty) {
                // Federate sends non-physical messages to other federates.
                // Initialize the downstream array.
                val numDownstream = federate.sendsTo.keySet.size
                // Allocate memory for the array.
                pr(rtiCode, '''
                    federates[«federate.id»].downstream = (int*)malloc(sizeof(federate_t*) * «numDownstream»);
                    federates[«federate.id»].num_downstream = «numDownstream»;
                ''')
                // Next, populate the array.
                // Find the minimum delay in the process.
                // FIXME: Zero delay is not really the same as a microstep delay.
                var count = 0;
                for (downstreamFederate : federate.sendsTo.keySet) {
                    pr(rtiCode, '''
                        federates[«federate.id»].downstream[«count»] = «downstreamFederate.id»;
                    ''')
                    count++;
                }
            }
        }
        
        // Start the RTI server before launching the federates because if it
        // fails, e.g. because the port is not available, then we don't want to
        // launch the federates.
        pr(rtiCode, '''
            int socket_descriptor = start_rti_server(«federationRTIProperties.get('port')»);
        ''')
        
        // Generate code that blocks until the federates resign.
        pr(rtiCode, "wait_for_federates(socket_descriptor);")
        
        unindent(rtiCode)
        pr(rtiCode, "}")
        
        var fOut = new FileOutputStream(
                new File(srcGenPath + File.separator + cFilename));
        fOut.write(rtiCode.toString().getBytes())
        fOut.close()
    }
    
    /** Create the launcher shell scripts. This will create one or two file
     *  in the output path (bin directory). The first has name equal to
     *  the filename of the source file without the ".lf" extension.
     *  This will be a shell script that launches the
     *  RTI and the federates.  If, in addition, either the RTI or any
     *  federate is mapped to a particular machine (anything other than
     *  the default "localhost" or "0.0.0.0"), then this will generate
     *  a shell script in the bin directory with name filename_distribute.sh
     *  that copies the relevant source files to the remote host and compiles
     *  them so that they are ready to execute using the launcher.
     * 
     *  A precondition for this to work is that the user invoking this
     *  code generator can log into the remote host without supplying
     *  a password. Specifically, you have to have installed your
     *  public key (typically found in ~/.ssh/id_rsa.pub) in
     *  ~/.ssh/authorized_keys on the remote host. In addition, the
     *  remote host must be running an ssh service.
     *  On an Arch Linux system using systemd, for example, this means
     *  running:
     * 
     *      sudo systemctl <start|enable> ssh.service
     * 
     *  Enable means to always start the service at startup, whereas
     *  start means to just start it this once.
     *  On MacOS, open System Preferences from the Apple menu and 
     *  click on the "Sharing" preference panel. Select the checkbox
     *  next to "Remote Login" to enable it.
     */
    def createLauncher() {
        // NOTE: It might be good to use screen when invoking the RTI
        // or federates remotely so you can detach and the process keeps running.
        // However, I was unable to get it working properly.
        // What this means is that the shell that invokes the launcher
        // needs to remain live for the duration of the federation.
        // If that shell is killed, the federation will die.
        // Hence, it is reasonable to launch the federation on a
        // machine that participates in the federation, for example,
        // on the machine that runs the RTI.  The command I tried
        // to get screen to work looks like this:
        // ssh -t «target» cd «path»; screen -S «filename»_«federate.name» -L bin/«filename»_«federate.name» 2>&1
        
        var outPath = directory + File.separator + "bin"

        val shCode = new StringBuilder()
        val distCode = new StringBuilder()
        pr(shCode, '''
            #!/bin/bash
            # Launcher for federated «filename».lf Lingua Franca program.
            # Uncomment to specify to behave as close as possible to the POSIX standard.
            # set -o posix
            # Set a trap to kill all background jobs on error.
            trap 'echo "#### Killing federates."; kill $(jobs -p)' ERR
            # Launch the federates:
        ''')
        val distHeader = '''
            #!/bin/bash
            # Distributor for federated «filename».lf Lingua Franca program.
            # Uncomment to specify to behave as close as possible to the POSIX standard.
            # set -o posix
        '''
        val host = federationRTIProperties.get('host')
        var target = host

        var path = federationRTIProperties.get('dir')
        if(path === null) path = 'LinguaFrancaRemote'

        var user = federationRTIProperties.get('user')
        if (user !== null) {
            target = user + '@' + host
        }
        for (federate : federates) {
            if (federate.host !== null && federate.host != 'localhost' && federate.host != '0.0.0.0') {
                if(distCode.length === 0) pr(distCode, distHeader)
                pr(distCode, '''
                    echo "Making directory «path» and subdirectories src-gen and path on host «federate.host»"
                    ssh «federate.host» mkdir -p «path»/src-gen «path»/bin «path»/log «path»/src-gen/core
                    pushd src-gen > /dev/null
                    echo "Copying source files to host «federate.host»"
                    scp «filename»_«federate.name».c ctarget.h «federate.host»:«path»/src-gen
                    scp core/reactor_common.c core/reactor.h core/pqueue.c core/pqueue.h core/util.h core/util.c core/reactor_threaded.c core/federate.c core/rti.h «federate.host»:«path»/src-gen/core/
                    popd > /dev/null
                    echo "Compiling on host «federate.host» using: «this.targetCompiler» -O2 src-gen/«filename»_«federate.name».c -o bin/«filename»_«federate.name» -pthread"
                    ssh «federate.host» 'cd «path»; «this.targetCompiler» -O2 src-gen/«filename»_«federate.name».c -o bin/«filename»_«federate.name» -pthread'
                ''')
                pr(shCode, '''
                    echo "#### Launching the federate «federate.name» on host «federate.host»"
                    ssh «federate.host» '\
                        cd «path»; bin/«filename»_«federate.name» >& log/«filename»_«federate.name».out; \
                        echo "****** Output from federate «federate.name» on host «federate.host»:"; \
                        cat log/«filename»_«federate.name».out; \
                        echo "****** End of output from federate «federate.name» on host «federate.host»"' &
                ''')                
            } else {
                pr(shCode, '''
                    echo "#### Launching the federate «federate.name»."
                    «outPath»«File.separator»«filename»_«federate.name» &
                ''')                
            }
        }
        // Launch the RTI in the foreground.
        if (host == 'localhost' || host == '0.0.0.0') {
            pr(shCode, '''
                echo "#### Launching the runtime infrastructure (RTI)."
                «outPath»«File.separator»«filename»_RTI
            ''')
        } else {
            // Copy the source code onto the remote machine and compile it there.
            if (distCode.length === 0) pr(distCode, distHeader)
            // The mkdir -p flag below creates intermediate directories if needed.
            pr(distCode, '''
                cd «path»
                echo "Making directory «path» and subdirectories src-gen and path on host «target»"
                ssh «target» mkdir -p «path»/src-gen «path»/bin «path»/log «path»/src-gen/core
                pushd src-gen > /dev/null
                echo "Copying source files to host «target»"
                 scp «filename»_RTI.c ctarget.h «target»:«path»/src-gen
                scp core/rti.c core/rti.h core/util.h core/util.c core/reactor.h core/pqueue.h «target»:«path»/src-gen/core
                popd > /dev/null
                echo "Compiling on host «target» using: «this.targetCompiler» -O2 «path»/src-gen/«filename»_RTI.c -o «path»/bin/«filename»_RTI -pthread"
                ssh «target» '«this.targetCompiler» -O2 «path»/src-gen/«filename»_RTI.c -o «path»/bin/«filename»_RTI -pthread'
            ''')

            // Launch the RTI on the remote machine using ssh and screen.
            // The -t argument to ssh creates a virtual terminal, which is needed by screen.
            // The -S gives the session a name.
            // The -L option turns on logging. Unfortunately, the -Logfile giving the log file name
            // is not standardized in screen. Logs go to screenlog.0 (or screenlog.n).
            // FIXME: Remote errors are not reported back via ssh from screen.
            // How to get them back to the local machine?
            // Perhaps use -c and generate a screen command file to control the logfile name,
            // but screen apparently doesn't write anything to the log file!
            //
            // The cryptic 2>&1 reroutes stderr to stdout so that both are returned.
            // The sleep at the end prevents screen from exiting before outgoing messages from
            // the federate have had time to go out to the RTI through the socket.
            pr(shCode, '''
                echo "#### Launching the runtime infrastructure (RTI) on remote host «host»."
                ssh «target» 'cd «path»; \
                    bin/«filename»_RTI >& log/«filename»_RTI.out; \
                    echo "------ output from «filename»_RTI on host «target»:"; \
                    cat log/«filename»_RTI.out; \
                    echo "------ end of output from «filename»_RTI on host «target»"'
            ''')
        }

        // Write the launcher file.
        // Delete file previously produced, if any.
        var file = new File(outPath + File.separator + filename)
        if (file.exists) {
            file.delete
        }
                
        var fOut = new FileOutputStream(file)
        fOut.write(shCode.toString().getBytes())
        fOut.close()
        if (!file.setExecutable(true, false)) {
            reportWarning(null, "Unable to make launcher script executable.")
        }
        
        // Write the distributor file.
        // Delete the file even if it does not get generated.
        file = new File(outPath + File.separator + filename + '_distribute.sh')
        if (file.exists) {
            file.delete
        }
        if (distCode.length > 0) {
            fOut = new FileOutputStream(file)
            fOut.write(distCode.toString().getBytes())
            fOut.close()
            if (!file.setExecutable(true, false)) {
                reportWarning(null, "Unable to make distributor script executable.")
            }
        }
    }
    
    /** 
     * Generate a reactor class definition for the specified federate.
     * A class definition has four parts:
     * 
     * * Preamble code, if any, specified in the Lingua Franca file.
     * * A "self" struct type definition (see the class documentation above).
     * * A function for each reaction.
     * * A constructor for creating an instance.
     * 
     * If the reactor is the main reactor, then
     * the generated code may be customized. Specifically,
     * if the main reactor has reactions, these reactions
     * will not be generated if they are triggered by or send
     * data to contained reactors that are not in the federate.
     * @param reactor The parsed reactor data structure.
     * @param federate A federate name, or null to unconditionally generate.
     */
    def generateReactorFederated(Reactor reactor, FederateInstance federate) {

        // Create Timer and Action for startup and shutdown, if they occur.
        handleStartupAndShutdown(reactor)
        
        // Create reactions to transfer data up the hierarchy.
        generateTransferOutputs(reactor)

        pr("// =============== START reactor class " + reactor.name)

        // Preamble code contains state declarations with static initializers.
        for (p : reactor.preambles ?: emptyList) {
            pr("// *********** From the preamble, verbatim:")
            prSourceLineNumber(p.code)
            pr(p.code.toText)
            pr("\n// *********** End of preamble.")
        }
        
        // Some of the following methods create lines of code that need to
        // go into the constructor.  Collect those lines of code here:
        val constructorCode = new StringBuilder()

        generateSelfStruct(reactor, federate, constructorCode)
        generateReactions(reactor, federate)
        generateConstructor(reactor, federate, constructorCode)
                
        pr("// =============== END reactor class " + reactor.name)
        pr("")
    }
    
    /**
     * Generate a constructor for the specified reactor in the specified federate.
     * @param reactor The parsed reactor data structure.
     * @param federate A federate name, or null to unconditionally generate.
     * @param constructorCode Lines of code previously generated that need to
     *  go into the constructor.
     */
    protected def generateConstructor(
        Reactor reactor, FederateInstance federate, StringBuilder constructorCode
    ) {
        val structType = selfStructType(reactor)
        pr('''
            «structType»* new_«reactor.name»() {
                «structType»* self = («structType»*)calloc(1, sizeof(«structType»));
                «constructorCode.toString»
                return self;
            }
        ''')
    }
    
    /**
     * Generate the self struct type definition for the specified reactor
     * in the specified federate.
     * @param reactor The parsed reactor data structure.
     * @param federate A federate name, or null to unconditionally generate.
     * @param constructorCode Place to put lines of code that need to
     *  go into the constructor.
     */
    protected def generateSelfStruct(
        Reactor reactor, FederateInstance federate, StringBuilder constructorCode
    ) {
        // Construct the typedef for the "self" struct.
        // First, create a type name for the self struct.
        val selfType = selfStructType(reactor)
        var body = new StringBuilder()
        // Start with parameters.
        for (parameter : reactor.allParameters) {
            prSourceLineNumber(body, parameter)
            pr(body, getParameterType(parameter) + ' ' + parameter.name + ';');
        }
        // Next handle states.
        for (stateVar : reactor.allStateVars) {
            prSourceLineNumber(body, stateVar)
            pr(body, getStateType(stateVar) + ' ' + stateVar.name + ';');
        }
        // Next handle inputs.
        for (input : reactor.allInputs) {
            prSourceLineNumber(body, input)
            
            // If the port is a multiport, create an array.
            var arraySpec = input.multiportArraySpec
            // If the input is a multiport, written as input[N] name:type;
            // then create an array 
            if (input.type === null) {
                reportError(input,
                    "Input is required to have a type: " + input.name)
            } else {
                val inputType = lfTypeToTokenType(input.inferredType)
                // If the input type has the form type[number], then treat it specially
                // to get a valid C type.
                val matcher = arrayPatternFixed.matcher(inputType)
                if (matcher.find()) {
                    // NOTE: Slightly obfuscate input name to help prevent accidental use.
                    // for int[10], the first match is int, the second [10].
                    // The following results in: int(* __foo)[10];
                    pr(body, '''«matcher.group(1)»(* __«input.name»)«arraySpec»«matcher.group(2)»;''');
                } else {
                    // NOTE: Slightly obfuscate input name to help prevent accidental use.
                    pr(body, inputType + '* __' + input.name + arraySpec + ';');
                }
                prSourceLineNumber(body, input)
                pr(body, 'bool* __' + input.name + '_is_present' + arraySpec + ';');
            }
        }

        // Find output ports that receive data from inside reactors
        // and put them into a HashMap for future use.
        // FIXME: Support multiports for this case.
        var outputToContainedOutput = new HashMap<Output, VarRef>();
        for (connection : reactor.connections) {
            // If the connection has the form c.x -> y, then it's what we are looking for.
            if (connection.rightPort.container === null &&
                connection.leftPort.container !== null) {
                if (connection.rightPort.variable instanceof Output) {
                    outputToContainedOutput.put(
                        connection.rightPort.variable as Output,
                        connection.leftPort
                    )
                } else {
                    reportError(
                        connection,
                        "Expected an output port but got " +
                            connection.rightPort.variable.name
                    )
                }
            }
        }

        // Next handle outputs.
        for (output : reactor.allOutputs) {
            prSourceLineNumber(body, output)
            // If the port is a multiport, create an array.
            var arraySpec = output.multiportArraySpec
            if (output.type === null) {
                reportError(output,
                    "Output is required to have a type: " + output.name)
            } else {
                // If the output type has the form type[] or type*, then change it to token_t*.
                val outputType = lfTypeToTokenType(output.inferredType)
                // If there are contained reactors that send data via this output,
                // then create a place to put the pointers to the sources of that data.
                var containedSource = outputToContainedOutput.get(output)
                // If the output type has the form type[number], then treat it specially
                // to get a valid C type.
                val matcher = arrayPatternFixed.matcher(outputType)
                if (matcher.find()) {
                    // Array case.
                    // NOTE: Slightly obfuscate output name to help prevent accidental use.
                    pr(body, matcher.group(1) + ' __' + output.name + arraySpec + matcher.group(2) + ';')
                    if (containedSource !== null) {
                        // This uses the same pattern as an input.
                        prSourceLineNumber(body, output)
                        pr(body, matcher.group(1) + '(* __' + output.name + '_inside)' + arraySpec + matcher.group(2) + ';')
                    }
                } else {
                    // Normal case or token_t* case.
                    // NOTE: Slightly obfuscate output name to help prevent accidental use.
                    pr(body, outputType + ' __' + output.name + arraySpec + ';')
                    // If there are contained reactors that send data via this output,
                    // then create a place to put the pointers to the sources of that data.
                    if (containedSource !== null) {
                        prSourceLineNumber(body, output)
                        pr(body, outputType + '* __' + output.name + '_inside' + arraySpec + ';')
                    }
                }
                // _is_present variables are the same for both cases.
                prSourceLineNumber(body, output)
                pr(body, 'bool __' + output.name + '_is_present' + arraySpec + ';')
                if (containedSource !== null) {
                    prSourceLineNumber(body, output)
                    pr(body, 'bool* __' + output.name + '_inside_is_present' + arraySpec + ';')
                }
                prSourceLineNumber(body, output)
                pr(body, 'int __' + output.name + '_num_destinations' + arraySpec + ';')
            }
        }
        
        // If there are contained reactors that either receive inputs
        // from reactions of this reactor or produce outputs that trigger
        // reactions of this reactor, then we need to create a struct
        // inside the self struct for each contained reactor. That
        // struct has a place to hold the data produced by this reactor's
        // reactions and a place to put pointers to data produced by
        // the contained reactors.
        // The contents of the struct will be collected first so that
        // we avoid duplicate entries and then the struct will be constructed.
        val structs = new HashMap<Instantiation,HashSet<Variable>>
        // For each variable so collected, if the variable is an output
        // of a contained reactor, then collect the indices of the reactions
        // that are triggered by it.
        val reactionsTriggered = new HashMap<Variable,HashSet<Integer>>
        
        var reactionCount = 0
        for (reaction : reactor.allReactions) {
            if (federate === null || federate.containsReaction(
                reactor,
                reaction
            )) {
                // First, handle reactions that produce outputs sent to inputs
                // of contained reactors.
                for (effect : reaction.effects ?: emptyList) {
                    if (effect.variable instanceof Input) {
                        var struct = structs.get(effect.container)
                        if (struct === null) {
                            struct = new HashSet<Variable>
                            structs.put(effect.container, struct)
                        }
                        struct.add(effect.variable)
                    }
                }
                // Second, handle reactions that are triggered by outputs
                // of contained reactors.
                for (TriggerRef trigger : reaction.triggers ?: emptyList) {
                    if (trigger instanceof VarRef) {
                        if (trigger.variable instanceof Output) {
                            var struct = structs.get(trigger.container)
                            if (struct === null) {
                                struct = new HashSet<Variable>
                                structs.put(trigger.container, struct)
                            }
                            struct.add(trigger.variable)

                            var triggered = reactionsTriggered.get(trigger.variable)
                            if (triggered === null) {
                                triggered = new HashSet<Integer>
                                reactionsTriggered.put(trigger.variable, triggered)
                            }
                            triggered.add(reactionCount)
                        }
                    }
                }
                // Third, handle reading (but not triggered by)
                // outputs of contained reactors.
                for (source : reaction.sources ?: emptyList) {
                    if (source.variable instanceof Output) {
                        var struct = structs.get(source.container)
                        if (struct === null) {
                            struct = new HashSet<Variable>
                            structs.put(source.container, struct)
                        }
                        struct.add(source.variable)
                    }
                }
            }
            // Increment the reaction count even if not in the federate for consistency.
            reactionCount++
        }
        for (containedReactor : structs.keySet) {
            pr(body, "struct {")
            indent(body)
            for (variable : structs.get(containedReactor)) {
                if (variable instanceof Input) {
                    pr(variable, body, '''
                        «lfTypeToTokenType(variable.inferredType)» «variable.name»;
                        bool «variable.name»_is_present;
                    ''')
                } else {
                    // Must be an output entry.
                    val port = variable as Output
                    // Outputs are pointers to the source of data.
                    pr(variable, body, '''
                        «lfTypeToTokenType(port.inferredType)»* «port.name»;
                        bool* «port.name»_is_present;
                        trigger_t «port.name»_trigger;
                    ''')
                    val triggered = reactionsTriggered.get(variable)
                    val triggeredSize = (triggered === null) ? 0 : triggered.size
                    if (triggeredSize > 0) {
                        pr(variable, body, '''
                            reaction_t* «port.name»_reactions[«triggeredSize»];
                        ''')
                        var triggeredCount = 0
                        for (index : triggered) {
                            pr(variable, constructorCode, '''
                                self->__«containedReactor.name».«port.name»_reactions[«triggeredCount++»] = &self->___reaction_«index»;
                            ''')
                        }
                        pr(variable, constructorCode, '''
                            self->__«containedReactor.name».«port.name»_trigger.reactions = self->__«containedReactor.name».«port.name»_reactions;
                        ''')
                    } else {
                        // Since the self struct is created using calloc, there is no need to set
                        // self->__«containedReactor.name».«port.name»_trigger.reactions = NULL
                    }
                    // Since the self struct is created using calloc, there is no need to set
                    // self->__«containedReactor.name».«port.name»_trigger.token = NULL;
                    // self->__«containedReactor.name».«port.name»_trigger.is_present = false;
                    // self->__«containedReactor.name».«port.name»_trigger.is_timer = false;
                    // self->__«containedReactor.name».«port.name»_trigger.is_physical = false;
                    // self->__«containedReactor.name».«port.name»_trigger.drop = false;
                    // self->__«containedReactor.name».«port.name»_trigger.element_size = 0;
                    pr(variable, constructorCode, '''
                        self->__«containedReactor.name».«port.name»_trigger.scheduled = NEVER;
                        self->__«containedReactor.name».«port.name»_trigger.number_of_reactions = «triggeredSize»;
                    ''')
                }
            }
            unindent(body)
            pr(body, "} __" + containedReactor.name + ';')
        }
        
        // Next, generate the fields needed for each reaction.
        generateReactionAndTriggerStructs(body, reactor, constructorCode, federate)
        
        if (body.length > 0) {
            pr('''
                typedef struct {
                    «body.toString»
                } «selfType»;
            ''')
        } else {
            // There are no fields for the self struct.
            // C compilers complain about empty structs, so we generate a placeholder.
            pr('''
                typedef struct {
                    bool hasContents;
                } «selfType»;
            ''')
        }
    }
    
    /**
     * Generate the fields of the self struct and statements for the constructor
     * to create an initialize a reaction_t struct for each reaction in the
     * specified reactor and a trigger_t struct for each trigger (input, action,
     * timer, or output of a contained reactor).
     * @param body The place to put the code for the self struct.
     * @param reactor The reactor.
     * @param constructorCode The place to put the constructor code.
     * @param federate The federate instance, or null if there is no federation.
     */
    protected def void generateReactionAndTriggerStructs(
        StringBuilder body, Reactor reactor, StringBuilder constructorCode, FederateInstance federate
    ) {
        var reactionCount = 0;
        // Iterate over reactions and create initialize the reaction_t struct
        // on the self struct. Also, collect a map from triggers to the reactions
        // that are triggered by that trigger. Also, collect a set of sources
        // that are read by reactions but do not trigger reactions.
        // Finally, collect a set of triggers and sources that are outputs
        // of contained reactors. 
        val triggerMap = new HashMap<Variable,LinkedList<Integer>>()
        val sourceSet = new HashSet<Variable>()
        val outputsOfContainedReactors = new HashMap<Variable,Instantiation>
        for (reaction : reactor.allReactions) {
            if (federate === null || federate.containsReaction(reactor, reaction)) {
                // Create the reaction_t struct.
                pr(reaction, body, '''reaction_t ___reaction_«reactionCount»;''')

                // Count the output ports and inputs of contained reactors that
                // may be set by this reactor. This ignores actions in the effects.
                // Also generate the constructor code to initialize the
                // _outputs_are_present array for the reaction.
                var outputCount = 0;
                for (effect : reaction.effects) {
                    if (effect.variable instanceof Port) {
                        // Create the entry in the _outputs_are_present array for this port.
                        // The port name may be something like "out" or "c.in", where "c" is a contained reactor.
                        pr(constructorCode, '''
                            self->__reaction_«reactionCount»_outputs_are_present[«outputCount»] = &self->__«ASTUtils.toText(effect)»_is_present;
                        ''')
                        outputCount++
                    }
                }
                // Create the map of triggers to reactions.
                for (trigger : reaction.triggers) {
                    // trigger may not be a VarRef (it could be "startup" or "shutdown").
                    if (trigger instanceof VarRef) {
                        var reactionList = triggerMap.get(trigger.variable)
                        if (reactionList === null) {
                            reactionList = new LinkedList<Integer>()
                            triggerMap.put(trigger.variable, reactionList)
                        }
                        reactionList.add(reactionCount)
                        if (trigger.container !== null) {
                            outputsOfContainedReactors.put(trigger.variable, trigger.container)
                        }
                    }
                }
                // Create the set of sources read but not triggering.
                for (source : reaction.sources) {
                    sourceSet.add(source.variable)
                    if (source.container !== null) {
                        outputsOfContainedReactors.put(source.variable, source.container)
                    }
                }

                pr(constructorCode, '''
                    self->__reaction_«reactionCount»_num_outputs = «outputCount»;
                ''')
                pr(body, '''
                    bool* __reaction_«reactionCount»_outputs_are_present[«outputCount»];
                    int __reaction_«reactionCount»_num_outputs;
                    trigger_t** __reaction_«reactionCount»_triggers[«outputCount»];
                    int __reaction_«reactionCount»_triggered_sizes[«outputCount»];
                ''')

                var deadlineFunctionPointer = "NULL"
                if (reaction.deadline !== null) {
                    // The following has to match the name chosen in generateReactions
                    val deadlineFunctionName = reactor.name.toLowerCase + '_deadline_function' + reactionCount
                    deadlineFunctionPointer = "&" + deadlineFunctionName
                }

                // Set the defaults of the reaction_t struct in the constructor.
                // Since the self struct is allocated using calloc, there is no need to set:
                // self->___reaction_«reactionCount».index = 0;
                // self->___reaction_«reactionCount».chain_id = 0;
                // self->___reaction_«reactionCount».pos = 0;
                // self->___reaction_«reactionCount».running = false;
                // self->___reaction_«reactionCount».deadline = 0LL;
                pr(reaction, constructorCode, '''
                    self->___reaction_«reactionCount».function = «reactionFunctionName(reactor, reactionCount)»;
                    self->___reaction_«reactionCount».self = self;
                    self->___reaction_«reactionCount».num_outputs = «outputCount»;
                    self->___reaction_«reactionCount».output_produced = self->__reaction_«reactionCount»_outputs_are_present;
                    self->___reaction_«reactionCount».triggered_sizes = self->__reaction_«reactionCount»_triggered_sizes;
                    self->___reaction_«reactionCount».triggers = self->__reaction_«reactionCount»_triggers;
                    self->___reaction_«reactionCount».deadline_violation_handler = «deadlineFunctionPointer»;
                ''')

            }
            // Increment the reactionCount even if the reaction is not in the federate
            // so that reaction indices are consistent across federates.
            reactionCount++
        }
        
        // Next, create and initialize the trigger_t objects.
        // Start with the timers.
        for (timer : reactor.allTimers) {
            createTriggerT(body, timer, triggerMap, constructorCode)
            // Since the self struct is allocated using calloc, there is no need to set:
            // self->___«timer.name».is_physical = false;
            // self->___«timer.name».drop = false;
            // self->___«timer.name».element_size = 0;
            pr(constructorCode, '''
                self->___«timer.name».is_timer = true;
            ''')
        }

        // Next handle actions.
        for (action : reactor.allActions) {
            createTriggerT(body, action, triggerMap, constructorCode)
            var isPhysical = "true";
            if (action.origin == ActionOrigin.LOGICAL) {
                isPhysical = "false";
            }
            var elementSize = "0"
            // If the action type is 'void', we need to avoid generating the code
            // 'sizeof(void)', which some compilers reject.
            if (action.type !== null && action.targetType.rootType != 'void') {
                elementSize = '''sizeof(«action.targetType.rootType»)'''
            }

            // Since the self struct is allocated using calloc, there is no need to set:
            // self->___«action.name».is_timer = false;
            pr(constructorCode, '''
                self->___«action.name».is_physical = «isPhysical»;
                self->___«action.name».drop = «action.drop»;
                self->___«action.name».element_size = «elementSize»;
            ''')
        }

        // Next handle inputs.
        for (input : reactor.inputs) {            
            createTriggerT(body, input, triggerMap, constructorCode)
        }
    }
    
    /**
     * Define the trigger_t object on the self struct, and array of
     * reaction_t pointers pointing to reactions triggered by this variable,
     * and initialize the pointers in the array in the constructor.
     * @param body The place to write the self struct entries.
     * @param variable The trigger variable (Timer, Action, or Port).
     * @param triggerMap A map from Variables to a list of the reaction indices
     *  triggered by the variable.
     * @param constructorCode The place to write the constructor code.
     */
    private def void createTriggerT(
        StringBuilder body, 
        Variable variable,
        HashMap<Variable, LinkedList<Integer>> triggerMap,
        StringBuilder constructorCode
    ) {
        prSourceLineNumber(body, variable)
        
        // To support multiports.
        var arraySpec = variable.multiportArraySpec
        
        // NOTE: This used to be a pointer to a static global variable, but
        // to better support mutations, the trigger_t struct is now part of the
        // self struct.
        pr(body, "trigger_t ___" + variable.name + arraySpec + ";")
        // Set generic defaults for the trigger_t struct.
        // Since the self struct is allocated using calloc, there is no need to set:
        // self->___«variable.name».token = NULL;
        // self->___«variable.name».is_present = false;
        // If the variable is a multiport, then there will be a for loop
        // surrounding this to set each element of the array of triggers.
        var indexSpec = ''
        if (arraySpec != '') {
            indexSpec = '[i]'
            // FIXME: here, the multiport width is assumed to be a property
            // of the class definition of the reactor, not the instance.
            // So there isn't any way to parameterize the width currently.
            // Perhaps the width should be a field on the self struct.
            pr(variable, constructorCode, '''
                for (int i = 0; i < «variable.multiportWidth»; i++) {
            ''')
            indent(constructorCode)
        }
        pr(variable, constructorCode, '''
            self->___«variable.name»«indexSpec».scheduled = NEVER;
        ''')
        // Generate the reactions triggered table.
        val reactionsTriggered = triggerMap.get(variable)
        if (reactionsTriggered !== null) {
            prSourceLineNumber(body, variable)
            pr(body, '''reaction_t* ___«variable.name»_reactions[«reactionsTriggered.size»]«arraySpec»;''')
            var count = 0
            for (reactionTriggered: reactionsTriggered) {
                prSourceLineNumber(constructorCode, variable)
                pr(constructorCode, '''
                    self->___«variable.name»_reactions[«count»]«indexSpec» = &self->___reaction_«reactionTriggered»;
                ''')
                count++
            }
            // Set up the trigger_t struct's pointer to the reactions.
            pr(constructorCode, '''
                self->___«variable.name»«indexSpec».reactions = &self->___«variable.name»_reactions[0]«indexSpec»;
                self->___«variable.name»«indexSpec».number_of_reactions = «count»;
            ''')
        }
        if (variable instanceof Input) {
            val rootType = variable.targetType.rootType
            // Since the self struct is allocated using calloc, there is no need to set:
            // self->___«input.name».is_timer = false;
            // self->___«input.name».offset = 0LL;
            // self->___«input.name».period = 0LL;
            // self->___«input.name».is_physical = false;
            // self->___«input.name».drop = false;
            // If the input type is 'void', we need to avoid generating the code
            // 'sizeof(void)', which some compilers reject.
            val size = (rootType == 'void')? '0' : '''sizeof(«rootType»)'''
            pr(constructorCode, '''
                self->___«variable.name»«indexSpec».element_size = «size»;
            ''')
        }
        if (arraySpec != '') {
            unindent(constructorCode)
            pr(variable, constructorCode, "}")
        }
    }
    
    
    /**
     * If any reaction in the specified reactor is triggered by startup,
     * then create a Timer to trigger that reaction. If any reaction
     * is triggered by shutdown, then create an action to trigger
     * that reaction. Only one timer or action will be created, even
     * if multiple reactions are triggered.
     * @param reactor The reactor.
     */
    protected def void handleStartupAndShutdown(Reactor reactor) {
        // Only one of each of these should be created even if multiple
        // reactions are triggered by them.
        var Timer timer = null
        var Action action = null
        var factory = LinguaFrancaFactory.eINSTANCE
        if (reactor.allReactions !== null) {
            for (Reaction reaction : reactor.allReactions) {
                // If the reaction triggers include 'startup' or 'shutdown',
                // then create Timer and TimerInstance objects named 'startup'
                // or Action and ActionInstance objects named 'shutdown'.
                // Using a Timer for startup means that the target-specific
                // code generator doesn't have to do anything special to support this.
                // However, for 'shutdown', the target-specific code generator
                // needs to check all reaction instances for a shutdownActionInstance
                // and schedule that action before shutting down the program.
                // These get inserted into both the ECore model and the
                // instance model.
                var TriggerRef startupTrigger = null;
                var TriggerRef shutdownTrigger = null;
                for (trigger : reaction.triggers) {
                    if (trigger.isStartup) {
                        startupTrigger = trigger
                        if (timer === null) {
                            timer = factory.createTimer
                            timer.name = LinguaFrancaPackage.Literals.
                                TRIGGER_REF__STARTUP.name
                            timer.offset = factory.createValue
                            timer.offset.literal = "0"
                            timer.period = factory.createValue
                            timer.period.literal = "0"
                            reactor.timers.add(timer)
                        }
                    } else if (trigger.isShutdown) {
                        shutdownTrigger = trigger
                        if (action === null) {
                            action = factory.createAction
                            action.name = LinguaFrancaPackage.Literals.
                                TRIGGER_REF__SHUTDOWN.name
                            action.origin = ActionOrigin.LOGICAL
                            action.minDelay = factory.createValue
                            action.minDelay.literal = "0"
                            reactor.actions.add(action)
                        }
                    }
                }
                // If appropriate, add a VarRef to the triggers list of this
                // reaction for the startup timer or shutdown action.
                if (startupTrigger !== null) {
                    reaction.triggers.remove(startupTrigger)
                    var variableReference = LinguaFrancaFactory.eINSTANCE.
                        createVarRef()
                    variableReference.setVariable(timer)
                    reaction.triggers.add(variableReference)
                }
                if (shutdownTrigger !== null) {
                    reaction.triggers.remove(shutdownTrigger)
                    var variableReference = LinguaFrancaFactory.eINSTANCE.
                        createVarRef()
                    variableReference.setVariable(action)
                    reaction.triggers.add(variableReference)
                }
            }
        }
    }

    /** Generate reaction functions definition for a reactor.
     *  These functions have a single argument that is a void* pointing to
     *  a struct that contains parameters, state variables, inputs (triggering or not),
     *  actions (triggering or produced), and outputs.
     *  @param reactor The reactor.
     *  @param federate The federate, or null if this is not
     *   federated or not the main reactor and reactions should be
     *   unconditionally generated.
     */
    def generateReactions(Reactor reactor, FederateInstance federate) {
        var reactionIndex = 0;
        for (reaction : reactor.allReactions) {
            if (federate === null || federate.containsReaction(reactor, reaction)) {
                generateReaction(reaction, reactor, reactionIndex)
            }
            // Increment reaction index even if the reaction is not in the federate
            // so that across federates, the reaction indices are consistent.
            reactionIndex++
        }
    }
    
    /** Generate a reaction function definition for a reactor.
     *  This function has a single argument that is a void* pointing to
     *  a struct that contains parameters, state variables, inputs (triggering or not),
     *  actions (triggering or produced), and outputs.
     *  @param reaction The reaction.
     *  @param reactor The reactor.
     *  @param reactionIndex The position of the reaction within the reactor. 
     */
    def generateReaction(Reaction reaction, Reactor reactor, int reactionIndex) {
        // Create a unique function name for each reaction.
        val functionName = reactionFunctionName(reactor, reactionIndex)

        // Construct the reactionInitialization code to go into
        // the body of the function before the verbatim code.
        var StringBuilder reactionInitialization = new StringBuilder()

        // Define the "self" struct.
        var structType = selfStructType(reactor)
        // A null structType means there are no inputs, state,
        // or anything else. No need to declare it.
        pr(reactionInitialization, structType + "* self = (" + structType + "*)instance_args;")

        // A reaction may send to or receive from multiple ports of
        // a contained reactor. The variables for these ports need to
        // all be declared as fields of the same struct. Hence, we first
        // collect the fields to be defined in the structs and then
        // generate the structs.
        var fieldsForStructsForContainedReactors = new HashMap<Instantiation, StringBuilder>

        // Actions may appear twice, first as a trigger, then with the outputs.
        // But we need to declare it only once. Collect in this data structure
        // the actions that are declared as triggered so that if they appear
        // again with the outputs, they are not defined a second time.
        // That second redefinition would trigger a compile error.  
        var actionsAsTriggers = new HashSet<Action>();

        // Next, add the triggers (input and actions; timers are not needed).
        // This defines a local variable in the reaction function whose
        // name matches that of the trigger. If the trigger is an input
        // or an action, then it also defines a local variable whose
        // name is the input/action name with suffix "_is_present", a boolean
        // that indicates whether the input/action is present.
        // If the trigger is an output, then it is an output of a
        // contained reactor. In this case, a struct with the name
        // of the contained reactor is created with two fields.
        // E.g., if the contained reactor is named 'c' and its output
        // port is named 'out', then c.out and c.out_is_present are
        // defined so that they can be used in the verbatim code.
        for (TriggerRef trigger : reaction.triggers ?: emptyList) {
            if (trigger instanceof VarRef) {
                if (trigger.variable instanceof Port) {
                    generatePortVariablesInReaction(reactionInitialization,
                        fieldsForStructsForContainedReactors, trigger)
                } else if (trigger.variable instanceof Action) {
                    generateActionVariablesInReaction(reactionInitialization, trigger.variable as Action)
                    actionsAsTriggers.add(trigger.variable as Action);
                }
            }
        }
        if (reaction.triggers === null || reaction.triggers.size === 0) {
            // No triggers are given, which means react to any input.
            // Declare an argument for every input.
            // NOTE: this does not include contained outputs. 
            for (input : reactor.inputs) {
                generateInputVariablesInReaction(reactionInitialization, input)
            }
        }
        // Define argument for non-triggering inputs.
        for (VarRef src : reaction.sources ?: emptyList) {
            if (src.variable instanceof Port) {
                generatePortVariablesInReaction(reactionInitialization, fieldsForStructsForContainedReactors, src)
            }
        }

        // Define variables for each declared output or action.
        // In the case of outputs, the variable is a pointer to where the
        // output is stored. This gives the reaction code access to any previous
        // value that may have been written to that output in an earlier reaction.
        // In addition, the _is_present variable is a boolean that indicates
        // whether the output has been written.
        if (reaction.effects !== null) {
            for (effect : reaction.effects) {
                // val action = getAction(reactor, output)
                if (effect.variable instanceof Action) {
                    // It is an action, not an output.
                    // If it has already appeared as trigger, do not redefine it.
                    if (!actionsAsTriggers.contains(effect.variable.name)) {
                        pr(reactionInitialization,
                            "trigger_t* " + effect.variable.name + ' = &self->___' + effect.variable.name + ';');
                    }
                } else {
                    if (effect.variable instanceof Output) {
                        generateOutputVariablesInReaction(reactionInitialization, effect.variable as Output)
                    } else if (effect.variable instanceof Input) {
                        // It is the input of a contained reactor.
                        generateVariablesForSendingToContainedReactors(
                            reactionInitialization,
                            fieldsForStructsForContainedReactors,
                            effect.container,
                            effect.variable as Input
                        )
                    } else {
                        reportError(
                            reaction,
                            "In generateReaction(): " + effect.variable.name + " is neither an input nor an output."
                        )
                    }
                }
            }
        }
        pr('void ' + functionName + '(void* instance_args) {')
        indent()
        var body = reaction.code.toText

        // Do not generate the initialization code if the body is marked
        // to not generate it.
        if (!body.startsWith(CGenerator.DISABLE_REACTION_INITIALIZATION_MARKER)) {
            // First generate the structs used for communication to and from contained reactors.
            for (containedReactor : fieldsForStructsForContainedReactors.keySet) {
                pr('struct ' + containedReactor.name + '{')
                indent();
                pr(fieldsForStructsForContainedReactors.get(containedReactor).toString)
                unindent();
                pr('} ' + containedReactor.name + ';')
            }
            // Next generate all the collected setup code.
            pr(reactionInitialization.toString)
        } else {
            pr(structType + "* self = (" + structType + "*)instance_args;")
        }
        // Code verbatim from 'reaction'
        prSourceLineNumber(reaction.code)
        pr(body)
        unindent()
        pr("}")

        // Now generate code for the deadline violation function, if there is one.
        if (reaction.deadline !== null) {
            // The following name has to match the choice in generateReactionInstances
            val deadlineFunctionName = reactor.name.toLowerCase + '_deadline_function' + reactionIndex

            pr('void ' + deadlineFunctionName + '(void* instance_args) {')
            indent();
            pr(reactionInitialization.toString)
            // Code verbatim from 'deadline'
            prSourceLineNumber(reaction.deadline.code)
            pr(reaction.deadline.code.toText)
            unindent()
            pr("}")
        }
    }

    /** Generate code to create the trigger table for each reaction of the
     *  specified reactor.  Each table lists the triggers that the reaction's
     *  execution may trigger. Each table is an array of arrays
     *  of pointers to the trigger_t structs representing the downstream inputs
     *  (or outputs of the container reactor) that are triggered by the reaction.
     *  Each trigger table goes into the reaction's reaction_t triggers field.
     *  That reaction_t struct is assumed to be on the self struct of the reactor
     *  instance with name "___reaction_i", where i is the index of the reaction.
     *  The generated code will also set the values of the triggered_sizes array
     *  on the reaction_t struct to indicate the size of each array of trigger_t
     *  pointers. The generated code will malloc each of these arrays, and the
     *  destructor for the reactor instance will free them.
     *  The generated code goes into the __initialize_trigger_objects() function.
     *  @param reactorIntance The reactor instance.
     *  @param federate The federate name or null if no federation.
     */
    def generateRemoteTriggerTable(ReactorInstance reactorInstance, FederateInstance federate) {
        val selfStruct = selfStructName(reactorInstance)
        var reactionCount = 0
        for (reaction : reactorInstance.reactions) {
            if (federate === null || federate.containsReaction(
                reactorInstance.definition.reactorClass,
                reaction.definition
            )) {
                var Collection<PortInstance> destinationPorts = null

                var portCount = 0
                for (port : reaction.dependentPorts) {
                    // The port to which the reaction writes may have dependent
                    // reactions in the container. If so, we list that port here.
                    var portsWithDependentReactions = new LinkedList<PortInstance>()

                    // The size of the array to be inserted into the triggers array of
                    // the reaction is the sum of the number of destination ports and
                    // the number of destination reactions (reactions of the container
                    // sensitive to this port.
                    var numberOfTriggerTObjects = 0

                    // Collect the destinations for each output port.
                    if (port.definition instanceof Output) {
                        // For each output, obtain the destinations from the parent.
                        // Pointers to the destination trigger_t objects will be collected into
                        // an array, which will become the 
                        var parent = reactorInstance.parent
                        if (parent !== null) {
                            destinationPorts = parent.transitiveClosure(port)
                        } else {
                            // At the top level, where there cannot be any destinations
                            // for an output port.
                            destinationPorts = new LinkedList<PortInstance>()
                        }

                        // The port may also have dependent reactions, which are
                        // reactions in the container of this port's container.
                        if (port.dependentReactions.size > 0) {
                            portsWithDependentReactions.add(port)
                            numberOfTriggerTObjects += port.dependentReactions.size
                        }
                    } else {
                        // The port is the input port of a contained reactor,
                        // use that reactor instance to compute the transitive closure.
                        destinationPorts = port.parent.transitiveClosure(port)
                    }

                    numberOfTriggerTObjects += destinationPorts.size

                    // Record this array size in reaction's reaction_t triggered_sizes array.
                    pr(initializeTriggerObjects, '''
                        // Reaction «reactionCount» of «reactorInstance.getFullName» triggers «numberOfTriggerTObjects» downstream reactions through port «port.getFullName».
                        «selfStruct»->___reaction_«reactionCount».triggered_sizes[«portCount»] = «numberOfTriggerTObjects»;
                    ''')
                    if (numberOfTriggerTObjects > 0) {
                        // Next, malloc the memory for the array and record its location.
                        // NOTE: Need a unique name for the pointer to the malloc'd array because some of the
                        // initialization has to occur at the end of __initialize_trigger_objects(), after
                        // all reactor instances have been created.
                        val triggerArray = '''«reactorInstance.uniqueID»_«reaction.reactionIndex»_«portCount»'''
                        pr(initializeTriggerObjects, '''
                            // For reaction «reactionCount» of «reactorInstance.getFullName», allocate an
                            // array of trigger pointers for downstream reactions through port «port.getFullName»
                            trigger_t** «triggerArray» = (trigger_t**)malloc(«numberOfTriggerTObjects» * sizeof(trigger_t*));
                            «selfStruct»->___reaction_«reactionCount».triggers[«portCount»] = «triggerArray»;
                        ''')

                        // Next, initialize the newly created array.
                        var destinationCount = 0;
                        for (destination : destinationPorts) {
                            // If the destination of a connection is an input
                            // port of a reactor that has no reactions to that input,
                            // then this trigger struct will not have been created.
                            // In that case, we want NULL.
                            // If the destination is an output port, however, then
                            // the dependentReactions.size reflects the number of downstream
                            // reactions. But we want only one trigger (for transfer outputs).
                            if (destination.dependentReactions.size === 0 || destination.isOutput) {
                                pr(initializeTriggerObjectsEnd, '''
                                    // Destination port «destination.getFullName» itself has no reactions.
                                    «triggerArray»[«destinationCount++»] = NULL;
                                ''')
                            } else {
                                pr(initializeTriggerObjectsEnd, '''
                                    // Point to destination port «destination.getFullName»'s trigger struct.
                                    «triggerArray»[«destinationCount++»] = &«triggerStructName(destination)»;
                                ''')
                            }
                        }
                        for (portWithDependentReactions : portsWithDependentReactions) {
                            for (destinationReaction : portWithDependentReactions.dependentReactions) {
                                if (reactorBelongsToFederate(destinationReaction.parent, federate)) {
                                    pr(initializeTriggerObjectsEnd, '''
                                        // Port «port.getFullName» has reactions in its parent's parent.
                                        // Point to the trigger struct for those reactions.
                                        «triggerArray»[«destinationCount++»] = &«triggerStructName(portWithDependentReactions, destinationReaction)»;
                                    ''')
                                }
                            }
                        }
                    }
                    portCount++
                }
            }
            // Increment reaction count even if it is not in the federate for consistency.
            reactionCount++
        }
    }

    /** Generate code to set up the tables used in __start_time_step to decrement reference
     *  counts and mark outputs absent between time steps. This function puts the code
     *  into startTimeStep.
     */
    def generateStartTimeStep(ReactorInstance instance, FederateInstance federate) {
        // First, set up to decrement reference counts for each token type
        // input of a contained reactor that is present.
        for (child : instance.children) {
            if (reactorBelongsToFederate(child, federate)) {
                var nameOfSelfStruct = selfStructName(child)
                for (input : child.inputs) {
                    if (isTokenType((input.definition as Input).inferredType)) {
                        pr(startTimeStep, '''
                            __tokens_with_ref_count[«startTimeStepTokens»].token
                                    = «nameOfSelfStruct»->__«input.name»;
                            __tokens_with_ref_count[«startTimeStepTokens»].is_present
                                    = «nameOfSelfStruct»->__«input.name»_is_present;
                            __tokens_with_ref_count[«startTimeStepTokens»].reset_is_present = false;
                        ''')
                        startTimeStepTokens++
                    }
                }
            }
        }
        var containerSelfStructName = selfStructName(instance)
        // Handle inputs that get sent data from a reaction rather than from
        // another contained reactor and reactions that are triggered by an
        // output of a contained reactor.
        for (reaction : instance.reactions) {
            if (federate === null || federate.containsReaction(
                instance.definition.reactorClass,
                reaction.definition
            )) {
                for (port : reaction.dependentPorts) {
                    if (port.definition instanceof Input) {
                        // This reaction is sending to an input. Must be
                        // the input of a contained reactor in the federate.
                        val sourcePort = sourcePort(port)
                        if (reactorBelongsToFederate(sourcePort.parent, federate)) {
                            pr(startTimeStep, '''
                                // Add port «sourcePort.getFullName» to array of _is_present fields.
                                __is_present_fields[«startTimeStepIsPresentCount»] 
                                        = &«containerSelfStructName»->__«sourcePort.parent.definition.name».«sourcePort.definition.name»_is_present;
                            ''')
                            startTimeStepIsPresentCount++
                        }
                    }
                }
                for (port : reaction.dependsOnPorts) {
                    if (port.definition instanceof Output) {
                        // This reaction is receiving data from the port.
                        if (isTokenType((port.definition as Output).inferredType)) {
                            pr(startTimeStep, '''
                                __tokens_with_ref_count[«startTimeStepTokens»].token
                                        = «containerSelfStructName»->__«port.parent.name».«port.name»;
                                __tokens_with_ref_count[«startTimeStepTokens»].is_present
                                        = «containerSelfStructName»->__«port.parent.name».«port.name»_is_present;
                                __tokens_with_ref_count[«startTimeStepTokens»].reset_is_present = false;
                            ''')
                            startTimeStepTokens++
                        }
                    }
                }
            }
        }
        // Next, set up the table to mark each output of each contained reactor absent.
        for (child : instance.children) {
            if (reactorBelongsToFederate(child, federate)) {
                var nameOfSelfStruct = selfStructName(child)
                for (output : child.outputs) {
                    pr(startTimeStep, '''
                        // Add port «output.getFullName» to array of _is_present fields.
                        __is_present_fields[«startTimeStepIsPresentCount»] = &«nameOfSelfStruct»->__«output.name»_is_present;
                    ''')
                    startTimeStepIsPresentCount++
                }
            }
        }
    }
    
    /** Generate one reaction function definition for each output of
     *  a reactor that relays data from the output of a contained reactor.
     *  This reaction function transfers the data from the output of the
     *  contained reactor (in the self struct of this reactor labeled as
     *  "inside") to the output of this reactor (also in its self struct).
     *  There needs to be one reaction function
     *  for each such output because these reaction functions have to be
     *  individually invoked after each contained reactor produces an
     *  output that must be relayed. These reactions are set up to not
     *  be required to be invoked in any particular order.
     *  @param reactor The reactor.
     */
    def generateTransferOutputs(Reactor reactor) {
        // FIXME: Is this really necessary? Couldn't the transitive closure function
        // of ReactorInstance traverse the hierarchy?
        for (connection : reactor.connections) {
            // If the connection has the form c.x -> y, then it's what we are looking for.
            if (connection.rightPort.container === null &&
                    connection.leftPort.container !== null) {
                if (connection.rightPort.variable instanceof Output) {
                    val reaction = ASTUtils.factory.createReaction()
                    // Mark this unordered relative to other reactions in the container.
                    // It will still be ordered by dependencies to the source.
                    reaction.makeUnordered()
                    val leftPort = ASTUtils.factory.createVarRef()
                    leftPort.container = connection.leftPort.container
                    leftPort.variable = connection.leftPort.variable
                    val rightPort = ASTUtils.factory.createVarRef()
                    rightPort.variable = connection.rightPort.variable
                    reaction.triggers.add(leftPort)
                    reaction.effects.add(rightPort)
                    reaction.code = factory.createCode()
                    if ((rightPort.variable as Port).inferredType.isTokenType) {
                        reaction.code.body = '''
                            «DISABLE_REACTION_INITIALIZATION_MARKER»
                            // Transfer output from «leftPort.toText» to «rightPort.toText» in «reactor.name»
                            self->__«rightPort.toText» = self->__«leftPort.toText»;
                            self->__«rightPort.toText»_is_present = true;
                        '''
                    } else {
                        reaction.code.body = '''
                            // Transfer output from «leftPort.toText» to «rightPort.toText» in «reactor.name»
                            set(«rightPort.toText», «leftPort.toText»);
                        '''
                    }
                    reactor.reactions.add(reaction)
                } else {
                    reportError(
                        connection,
                        "Expected an output port but got " +
                            connection.rightPort.variable.name
                    )
                }
            }
        }
    }

    /**
     * For each timer and action in the specified reactor instance, generate
     * initialization code for the offset and period fields. This code goes into
     * __initialize_trigger_objects(). This has to be done separately for each
     * instance, rather than by the constructor, because the values of the offset
     * and period may be given by parameters, so the values are potentially
     * different for each instance.
     * 
     * This method will also populate the global __timer_triggers array, which is
     * used to start all timers at the start of execution.
     * 
     * @param reactorInstance The instance for which we are generating trigger objects.
     * @return A map of trigger names to the name of the trigger struct.
     */
    def generateOffsetAndPeriodInitializations(ReactorInstance reactorInstance) {
        var count = 0
        // Iterate over triggers (input ports, actions, and timers that trigger reactions).
        for (triggerInstance : reactorInstance.triggersAndReads) {
            var trigger = triggerInstance.definition
            var triggerStructName = triggerStructName(triggerInstance)
            if (trigger instanceof Timer) {
                val offset = timeInTargetLanguage((triggerInstance as TimerInstance).offset)
                val period = timeInTargetLanguage((triggerInstance as TimerInstance).period)
                pr(initializeTriggerObjects, '''
                    «triggerStructName».offset = «offset»;
                    «triggerStructName».period = «period»;
                    __timer_triggers[«startTimersCount»] = &«triggerStructName»;
                ''')
                startTimersCount++
            } else if (trigger instanceof Action) {
                var minDelay = (triggerInstance as ActionInstance).minDelay
                var minInterArrival = (triggerInstance as ActionInstance).minInterArrival
                pr(initializeTriggerObjects, '''
                    «triggerStructName».offset = «timeInTargetLanguage(minDelay)»;
                    «triggerStructName».period = «timeInTargetLanguage(minInterArrival)»;
                ''')               
            } else if (triggerInstance instanceof PortInstance) {
                // Nothing to do in initialize_trigger_objects
            } else {
                reportError(trigger,
                    "Internal error: Seems to not be a port, timer, or action: " +
                        trigger.name)
            }
            count++
            triggerCount++
        }
    }

    /** Open a non-Lingua Franca import file at the specified URI
     *  in the specified resource set. Throw an exception if the
     *  file import is not supported. This class imports .proto files
     *  and runs, if possible, the protoc protocol buffer code generator
     *  to produce the required .h and .c files.
     *  @param importStatement The original import statement (used for error reporting).
     *  @param resourceSet The resource set in which to find the file.
     *  @param resolvedURI The URI to import.
     */
    override openForeignImport(Import importStatement, ResourceSet resourceSet, URI resolvedURI) {
        // Unfortunately, the resolvedURI appears to be useless for ordinary files
        // (non-xtext files). Use the original importStatement.importURI
        if (importStatement.importURI.endsWith(".proto")) {
            // FIXME: Should we include protoc-c as a submodule? If so, how to invoke it?
            // protoc is commonly installed in /usr/local/bin, which sadly is not by
            // default on the PATH for a Mac.
            // Invoke protoc-c.
            val protocCommand = newArrayList
            protocCommand.addAll("protoc-c", "--c_out=src-gen", importStatement.importURI)
            if (executeCommand(protocCommand, directory) != 0) {
                return reportError(importStatement, "Protocol buffer compiler failed."
                    + "\nFor installation instructions, see: https://github.com/protobuf-c/protobuf-c."
                    + "\nMake sure that your PATH variable includes the directory where protoc-c is installed,"
                    + "\ntypically /usr/local/bin. You can set PATH in ~/.bash_profile on Linux or Mac.")
            }
            if (compileAdditionalSources === null) {
                compileAdditionalSources = newArrayList
            }
            // Strip the ".proto" off the file name.
            // NOTE: This assumes that the filename matches the generated files, which it seems to.
            val rootFilename = importStatement.importURI.substring(0, importStatement.importURI.length - 6)
            compileAdditionalSources.add("src-gen" + File.separator + rootFilename + ".pb-c.c")
            
            // The -l protobuf-c command-line option should be added only once, even if there
            // are multiple protobuf imports.
            if (compileLibraries === null) {
                compileLibraries = newArrayList
                compileLibraries.add('-l')
                compileLibraries.add('protobuf-c')
            }
        } else {
            return reportError(importStatement, "Unsupported imported file type: "
                + importStatement.importURI
            )
        }
        return "OK"
    }

    /**
     * Open an import at the Lingua Franca file at the specified URI in the
     * specified resource, find all non-main reactors, and add them to the
     * {@link #GeneratorBase.reactors reactors}.
     * @param importStatement The import statement.
     * @param resourceSet The resource set in which to find the file.
     * @param resolvedURI The URI to import.
     * @return The imported resource or null if the import fails.
     */
    override openLFImport(Import importStatement, ResourceSet resourceSet, URI resolvedURI) {
        prSourceLineNumber(importStatement)
        super.openLFImport(importStatement, resourceSet, resolvedURI)
    }
    
    /**
     * Return a string for referencing the data or is_present value of
     * the specified port. This is used for establishing the destination of
     * data for a connection between ports.
     * This will have one of the following forms:
     * 
     * * selfStruct->__portName
     * * selfStruct->__portName_inside
     * * selfStruct->__portName[i]
     * * selfStruct->__portName_inside[i]
     * 
     * The '_inside' is inserted if the port is an output, and the [i]
     * is appended if it is a multiport, where i is the index of the
     * port within the multiport.
     * 
     * @param port An instance of a destination port.
     * @param isPresent If true, return a reference to the is_present
     *  variable rather than the value.
     */
    static def destinationReference(PortInstance port, boolean isPresent) {
         var destStruct = selfStructName(port.parent)

        // If the destination is in a multiport, find its index.
        var destinationIndexSpec = ''
        if (port.multiportIndex >= 0) {
            destinationIndexSpec = '[' + port.multiportIndex + ']'
        }
        
        val isPresentSpec = isPresent? '_is_present' : ''
        
        if (port.isInput) {
            return '''«destStruct»->__«port.name»«isPresentSpec»«destinationIndexSpec»'''
        } else {
            return '''«destStruct»->__«port.name»_inside«isPresentSpec»«destinationIndexSpec»'''
        }        
    }
 
    /**
     * Return a string for referencing the data or is_present value in
     * a self struct that received data from the specified output port
     * to be used by a reaction. The output port is contained by a
     * This will have one of the following forms:
     * 
     * * selfStruct->__reactorName.portName
     * * selfStruct->__reactorName.portName_is_present
     * * selfStruct->__reactorName.portName[i]
     * * selfStruct->__reactorName.portName_is_present[i]
     * 
     * The selfStruct is that of the container of reactor that
     * contains the port. If the port is in a multiport, then i is
     * the index of the port within the multiport.
     * 
     * @param port An instance of a destination port.
     * @param isPresent If true, return a reference to the is_present
     *  variable rather than the value.
     */
    static def reactionReference(PortInstance port, boolean isPresent) {
         var destStruct = selfStructName(port.parent.parent)

        // If the destination is in a multiport, find its index.
        var destinationIndexSpec = ''
        if (port.multiportIndex >= 0) {
            destinationIndexSpec = '[' + port.multiportIndex + ']'
        }
        
        val isPresentSpec = isPresent? '_is_present' : ''
        
        if (port.isOutput) {
            return '''«destStruct»->__«port.parent.name».«port.name»«isPresentSpec»«destinationIndexSpec»'''
        } else {
            return '// Nothing to do. Port is an input.'
        }
    }
 
    /**
     * Return a string for referencing the data or is_present value of
     * the specified port. This is used for establishing the source of
     * data for a connection between ports.
     * This will have one of the following forms:
     * 
     * * selfStruct->__portName
     * * selfStruct->__parentName.portName
     * * selfStruct->__portName[i]
     * * selfStruct->__parentName.portName[i]
     * 
     * If the port depends on another port, then this will reference
     * the eventual upstream port where the data is store. W.g., it is an input that
     * connected to upstream output, then portName will be the name
     * of the upstream output and the selfStruct will be that of the
     * upstream reactor. If the port is an input port that is written to
     * by a reaction of the parent of the port's parent, then the selfStruct
     * will be that of the parent of the port's parent, and parentName
     * will the name of the port's parent.
     * If the port is an output, then selfStruct will be the parent's
     * selfStruct and the portName will be the name of the port.
     * If the port is a multiport, then one of the last two forms will
     * be used, where i is the index of the multiport.
     * 
     * @param port An instance of the port to be referenced.
     * @param isPresent If true, return a reference to the is_present
     *  variable rather than the value.
     */
    static def sourceReference(PortInstance port, boolean isPresent) {
        // If the port depends on another port, find the ultimate source port,
        // which could be the input port if it is written to by a reaction
        // or it could be an upstream output port. 
        var eventualSource = sourcePort(port)
        
        // If it is in a multiport, find its index.          
        var sourceIndexSpec = ''
        if (eventualSource.multiportIndex >= 0) {
            sourceIndexSpec = '[' + eventualSource.multiportIndex + ']'
        }
        
        val isPresentSpec = isPresent? '_is_present' : ''
        
        if (eventualSource.isOutput) {
            val sourceStruct = selfStructName(eventualSource.parent)
            return '''«sourceStruct»->__«eventualSource.name»«isPresentSpec»«sourceIndexSpec»'''
        } else {
            val sourceStruct = selfStructName(eventualSource.parent.parent)
            return '''«sourceStruct»->__«eventualSource.parent.name».«eventualSource.name»«isPresentSpec»«sourceIndexSpec»'''
        }
    }

    /** Return the unique name for the "self" struct of the specified
     *  reactor instance from the instance ID.
     *  @param instance The reactor instance.
     *  @return The name of the self struct.
     */
    static def selfStructName(ReactorInstance instance) {
        return instance.uniqueID + "_self"
    }

    /** Construct a unique type for the "self" struct of the specified
     *  reactor class from the reactor class.
     *  @param instance The reactor instance.
     *  @return The name of the self struct.
     */
    def selfStructType(Reactor reactor) {
        return reactor.name.toLowerCase + "_self_t"
    }
    
    /** Return the function name for specified reaction of the
     *  specified reactor.
     *  @param reactor The reactor
     *  @param reactionIndex The reaction index.
     *  @return The function name for the reaction.
     */
    def reactionFunctionName(Reactor reactor, int reactionIndex) {
          reactor.name.toLowerCase + "reaction_function_" + reactionIndex
    }

    /** Return a reference to the trigger_t struct of the specified
     *  trigger instance (input port or action). This trigger_t struct
     *  is on the self struct.
     *  @param instance The port or action instance.
     *  @return The name of the trigger struct.
     */
    static def triggerStructName(TriggerInstance<Variable> instance) {
        var index = ''
        if (instance instanceof PortInstance) {
            if (instance.multiportIndex >= 0) {
                index = '[' + instance.multiportIndex + ']'
            }
        }
        return selfStructName(instance.parent) 
                + '->___'
                + instance.name
                + index
    }
    
    /** Return a reference to the trigger_t struct for the specified output
     *  port of a contained reactor that triggers the specified reaction.
     *  @param port The output port of a contained reactor.
     *  @param reaction The reaction triggered by this port.
     *  @return The name of the trigger struct, which is in the self struct
     *   of the container of the reaction.
     */
    static def triggerStructName(PortInstance port, ReactionInstance reaction) {
        return '''«selfStructName(reaction.parent)»->__«port.parent.name».«port.name»_trigger;'''
    }

    /** Traverse the runtime hierarchy of reaction instances and generate code.
     *  @param instance A reactor instance.
     *  @param federate A federate name to conditionally generate code by
     *   contained reactors or null if there are no federates.
     */
    def void generateReactorInstance(ReactorInstance instance, FederateInstance federate) {
        // If this is not the main reactor and is not in the federate, nothing to do.
        if (instance !== this.main && !reactorBelongsToFederate(instance, federate)) {
            return
        }
        var reactorClass = instance.definition.reactorClass
        var fullName = instance.fullName
        pr(initializeTriggerObjects, '// ************* Instance ' + fullName + ' of class ' +
            reactorClass.name)

        // Generate the instance struct containing parameters, state variables,
        // and outputs (the "self" struct).
        var nameOfSelfStruct = selfStructName(instance)
        var structType = selfStructType(reactorClass)
        pr(initializeTriggerObjects, '''
            «structType»* «nameOfSelfStruct» = new_«reactorClass.name»();
        ''')

        // Generate code to initialize the "self" struct in the
        // __initialize_trigger_objects function.
        pr(initializeTriggerObjects, "//***** Start initializing " + fullName)

        // Start with parameters.
        for (parameter : instance.parameters) {
            // NOTE: we now use the resolved literal value. For better efficiency, we could
            // store constants in a global array and refer to its elements to avoid duplicate
            // memory allocations.
            
            // Array type parameters have to be handled specially.
            val matcher = arrayPatternVariable.matcher(parameter.type.targetType)
            if (matcher.find()) {
                // Use an intermediate temporary variable so that parameter dependencies
                // are resolved correctly.
                val temporaryVariableName = parameter.uniqueID
                pr(initializeTriggerObjects,
                    "static " + matcher.group(1) + " " +
                    temporaryVariableName + "[] = " + parameter.getInitializer + ";"
                )
                pr(initializeTriggerObjects,
                    nameOfSelfStruct + "->" + parameter.name + " = " + temporaryVariableName + ";"
                )
            } else {
                pr(initializeTriggerObjects,
                    nameOfSelfStruct + "->" + parameter.name + " = " +
                        parameter.getInitializer + ";" 
                )
            }
        }

        // Next, initialize the "self" struct with state variables.
        // These values may be expressions that refer to the parameter values defined above.
        
        for (stateVar : reactorClass.stateVars) {
            
            val initializer = getInitializer(stateVar, instance)
            if (stateVar.initialized) {
	          	if (stateVar.isOfTimeType) {
	                pr(initializeTriggerObjects,
	                    nameOfSelfStruct + "->" + stateVar.name + " = " +
	                        initializer + ";")
	            } else {
	                // If the state is initialized with a parameter, then do not use
	                // a temporary variable. Otherwise, do, because
	                // static initializers for arrays and structs have to be handled
	                // this way, and there is no way to tell whether the type of the array
	                // is a struct.
	                if (stateVar.isParameterized && stateVar.init.size > 0) {
	                    pr(initializeTriggerObjects,
	                        nameOfSelfStruct + "->" + stateVar.name + " = " + initializer + ";")
	                } else {
	                   val temporaryVariableName = instance.uniqueID + '_initial_' + stateVar.name
	                    var type = stateVar.targetType
	                    val matcher = arrayPatternVariable.matcher(type)
	                    if (matcher.find()) {
	                        // If the state type ends in [], then we have to move the []
	                        // because C is very picky about where this goes. It has to go
	                        // after the variable name.
	                        pr(initializeTriggerObjects,
	                            "static " + matcher.group(1) + " " +
	                            temporaryVariableName + "[] = " + initializer + ";"
	                        )
	                    } else {
	                        pr(initializeTriggerObjects,
	                            "static " + type + " " +
	                            temporaryVariableName + " = " + initializer + ";"
	                        )
	                    }
	                    pr(initializeTriggerObjects,
	                        nameOfSelfStruct + "->" + stateVar.name + " = " + temporaryVariableName + ";"
	                    ) 
	                }
	            }	
            }
        }

        // Generate reaction structs for the instance.
        generateRemoteTriggerTable(instance, federate)

        // Generate trigger objects for the instance.
        generateOffsetAndPeriodInitializations(instance)

        // Next, set the number of destinations,
        // which is used to initialize reference counts.
        // Reference counts are decremented by each destination reactor
        // at the conclusion of a time step. Hence, the initial reference
        // count should equal the number of destination _reactors_, not the
        // number of destination ports nor the number of destination reactions.
        // One of the destination reactors may be the container of this
        // instance because it may have a reaction to an output of this instance. 
        for (output : instance.outputs) {
            // Count the number of destination reactors that receive data from
            // this output port. Do this by building a set of the containers
            // of all dependent ports and reactions. The dependentReactions
            // includes reactions of the container that listen to this port.
            val destinationReactors = new HashSet<ReactorInstance>()
            for (destinationPort : output.dependentPorts) {
                destinationReactors.add(destinationPort.parent)
            }
            for (destinationReaction : output.dependentReactions) {
                destinationReactors.add(destinationReaction.parent)
            }
            var numDestinations = destinationReactors.size
            pr(initializeTriggerObjects, '''
                «nameOfSelfStruct»->__«output.name»_num_destinations = «numDestinations»;
            ''')
        }
        
        // Next, initialize actions by creating a token_t in the self struct.
        // This has the information required to allocate memory for the action payload.
        // Skip any action that is not actually used as a trigger.
        val triggersInUse = instance.triggers
        for (action : instance.actions) {
            // Skip this step if the action is not in use. 
            if (triggersInUse.contains(action)) {
                var type = (action.definition as Action).inferredType
                var payloadSize = "0"
                
                if (!type.isUndefined) {
                    var String typeStr = type.targetType
                    if (isTokenType(type)) {
                        typeStr = typeStr.rootType
                    } else {
                        typeStr = type.targetType
                    }
                    if (typeStr !== null && !typeStr.equals("") && !typeStr.equals("void")) {
                        payloadSize = '''sizeof(«typeStr»)'''
                    }    
                }
            
                // Create a reference token initialized to the payload size.
                // This token is marked to not be freed so that the trigger_t struct
                // always has a reference token.
                pr(initializeTriggerObjects,
                    '''
                    «nameOfSelfStruct»->___«action.name».token = __create_token(«payloadSize»);
                    «nameOfSelfStruct»->___«action.name».is_present = false;
                    '''
                )
                // At the start of each time step, we need to initialize the is_present field
                // of each action's trigger object to false and free a previously
                // allocated token if appropriate. This code sets up the table that does that.
                pr(initializeTriggerObjects, '''
                    __tokens_with_ref_count[«startTimeStepTokens»].token
                            = &«nameOfSelfStruct»->___«action.name».token;
                    __tokens_with_ref_count[«startTimeStepTokens»].is_present
                            = &«nameOfSelfStruct»->___«action.name».is_present;
                    __tokens_with_ref_count[«startTimeStepTokens»].reset_is_present = true;
                ''')
                startTimeStepTokens++
            }
        }
        // Handle reaction local deadlines.
        var reactionCount = 0
        for (reaction : instance.reactions) {
            if (federate === null || federate.containsReaction(
                instance.definition.reactorClass,
                reaction.definition
            )) {
                if (reaction.declaredDeadline !== null) {
                    var deadline = reaction.declaredDeadline.maxDelay
                    val reactionStructName = '''«selfStructName(reaction.parent)»->___reaction_«reactionCount»'''
                    pr(initializeTriggerObjects, '''
                        «reactionStructName».deadline = «timeInTargetLanguage(deadline)»;
                    ''')
                }

            }
            // Increment the reaction count even if not in the federate for conistency.
            reactionCount++;
        }
        for (child : instance.children) {
            if (reactorBelongsToFederate(child, federate)) {
                generateReactorInstance(child, federate)
            }
        }
        
        // For this instance, define what must be done at the start of
        // each time step. This sets up the tables that are used by the
        // __start_time_step() function in reactor_common.c.
        // Note that this function is also run once at the end
        // so that it can deallocate any memory.
        generateStartTimeStep(instance, federate)

        pr(initializeTriggerObjects, "//***** End initializing " + fullName)
    }
    
    
    protected def getInitializer(StateVar state, ReactorInstance parent) {
        var list = new LinkedList<String>();

        for (i : state?.init) {
            if (i.parameter !== null) {
                list.add(parent.selfStructName + "->" + i.parameter.name)
            } else if (state.isOfTimeType) {
                list.add(i.targetTime)
            } else {
                list.add(i.targetValue)
            }
        }
        
        if (list.size == 1)
            return list.get(0)
        else
            return list.join('{', ', ', '}', [it])
    }
    
    /** Return true if the specified reactor instance belongs to the specified
     *  federate. This always returns true if the specified federate is
     *  null or a singleton. Otherwise, it returns true only if the
     *  instance is contained by the main reactor and the instance name
     *  was included in the 'reactors' property of the targets 'federates'
     *  specification.
     *  @param instance A reactor instance.
     *  @param federate A federate null if there are no federates.
     */
    def reactorBelongsToFederate(ReactorInstance instance, FederateInstance federate) {
        if (federate === null || federate.isSingleton) {
            return true
        } else {
            if (instance.parent === this.main 
                && !federate.contains(instance.name)
            ) {
                return false
            } else {
                return true
            }
        }
    }

    /** Set the reaction priorities based on dependency analysis.
     *  @param reactor The reactor on which to do this.
     *  @param federate A federate to conditionally generate code for
     *   contained reactors or null if there are no federates.
     */
    def void setReactionPriorities(ReactorInstance reactor, FederateInstance federate) {
        // Use "reactionToReactionTName" property of reactionInstance
        // to set the levels.
        var reactionCount = 0
        for (reactionInstance : reactor.reactions) {
            if (federate === null || federate.containsReaction(
                reactor.definition.reactorClass,
                reactionInstance.definition
            )) {
                val reactionStructName = '''«selfStructName(reactionInstance.parent)»->___reaction_«reactionCount»'''
                val reactionIndex = "0x" + (reactionInstance.deadline.toNanoSeconds.shiftLeft(16)).or(
                    new BigInteger(reactionInstance.level.toString)).toString(16) + "LL"
                pr('''
                    «reactionStructName».chain_id = «reactionInstance.chainID.toString»;
                    // index is the OR of level «reactionInstance.level» and 
                    // deadline «reactionInstance.deadline.toNanoSeconds» shifted left 16 bits.
                    «reactionStructName».index = «reactionIndex»;
                ''')
            }
            // Increment reaction count even if it is not in the federate for consistency.
            reactionCount++;
        }
        for (child : reactor.children) {
            if (reactorBelongsToFederate(child, federate)) {
                setReactionPriorities(child, federate)
            }
        }
    }

    // //////////////////////////////////////////
    // // Protected methods.

    /** Return a set of targets that are acceptable to this generator.
     *  Imported files that are Lingua Franca files must specify targets
     *  in this set or an error message will be reported and the import
     *  will be ignored. The returned set contains only "C".
     */
    override acceptableTargets() {
        acceptableTargetSet
    }

    /**
     * Generate code for the body of a reaction that takes an input and
     * schedules an action with the value of that input.
     * @param action The action to schedule
     * @param port The port to read from
     */
    override generateDelayBody(Action action, VarRef port) { 
        val ref = generateVarRef(port);
        // Note that the action.type set by the base class is actually
        // the port type.
        if (action.inferredType.isTokenType) {
            '''
            if («ref»_is_present) {
                // Put the whole token on the event queue, not just the payload.
                // This way, the length and element_size are transported.
                schedule_token(«action.name», 0, «ref»_token);
            }
            '''
        } else {
            '''
            schedule_copy(«action.name», 0, &«ref», 1);  // Length is 1.
            '''
        }
    }
    
    /**
     * Generate code for the body of a reaction that is triggered by the
     * given action and writes its value to the given port. This realizes
     * the receiving end of a logical delay specified with the 'after'
     * keyword.
     * @param action The action that triggers the reaction
     * @param port The port to write to.
     */
    override generateForwardBody(Action action, VarRef port) {
        val outputName = generateVarRef(port)
        if (action.inferredType.isTokenType) {
            // Forward the entire token and prevent freeing.
            // Increment the ref_count because it will be decremented
            // by both the action handling code and the input handling code.
            '''
            «DISABLE_REACTION_INITIALIZATION_MARKER»
            self->__«outputName» = (token_t*)self->___«action.name».token;
            ((token_t*)self->___«action.name».token)->ref_count++;
            self->__«outputName»_is_present = true;
            '''
        } else {
            '''
            set(«outputName», «action.name»_value);
            '''
        }
    }

    /**
     * Generate code for the body of a reaction that handles the
     * action that is triggered by receiving a message from a remote
     * federate.
     * @param action The action.
     * @param sendingPort The output port providing the data to send.
     * @param receivingPort The ID of the destination port.
     * @param receivingPortID The ID of the destination port.
     * @param sendingFed The sending federate.
     * @param receivingFed The destination federate.
     * @param type The type.
     */
    override generateNetworkReceiverBody(
        Action action,
        VarRef sendingPort,
        VarRef receivingPort,
        int receivingPortID, 
        FederateInstance sendingFed,
        FederateInstance receivingFed,
        InferredType type
    ) {
        // Adjust the type of the action and the receivingPort.
        // If it is "string", then change it to "char*".
        // This string is dynamically allocated, and type 'string' is to be
        // used only for statically allocated strings.
        if (action.type.targetType == "string") {
            action.type.code = null
            action.type.id = "char*"
        }
        if ((receivingPort.variable as Port).type.targetType == "string") {
            (receivingPort.variable as Port).type.code = null
            (receivingPort.variable as Port).type.id = "char*"
        }

        val sendRef = generateVarRef(sendingPort)
        val receiveRef = generateVarRef(receivingPort)
        val result = new StringBuilder()
        result.append('''
            // Receiving from «sendRef» in federate «sendingFed.name» to «receiveRef» in federate «receivingFed.name»
        ''')
        if (isTokenType(type)) {
            result.append('''
                set(«receiveRef», «action.name»_token);
                «action.name»_token->ref_count++;
            ''')
        } else {
            // NOTE: Docs say that malloc'd char* is freed on conclusion of the time step.
            // So passing it downstream should be OK.
            result.append('''
                set(«receiveRef», «action.name»_value);
            ''')
        }
        return result.toString
    }

    /**
     * Generate code for the body of a reaction that handles an output
     * that is to be sent over the network.
     * @param sendingPort The output port providing the data to send.
     * @param receivingPort The ID of the destination port.
     * @param receivingPortID The ID of the destination port.
     * @param sendingFed The sending federate.
     * @param receivingFed The destination federate.
     * @param type The type.
     */
    override generateNetworkSenderBody(
        VarRef sendingPort,
        VarRef receivingPort,
        int receivingPortID, 
        FederateInstance sendingFed,
        FederateInstance receivingFed,
        InferredType type
    ) { 
        val sendRef = generateVarRef(sendingPort)
        val receiveRef = generateVarRef(receivingPort)
        val result = new StringBuilder()
        result.append('''
            // Sending from «sendRef» in federate «sendingFed.name» to «receiveRef» in federate «receivingFed.name»
        ''')
        // FIXME: Use send_via_rti if the physical keyword is supplied to the connection.
        if (isTokenType(type)) {
            // NOTE: Transporting token types this way is likely to only work if the sender and receiver
            // both have the same endianess. Otherwise, you have to use protobufs or some other serialization scheme.
            result.append('''
                size_t message_length = «sendRef»->length * «sendRef»->element_size;
                «sendRef»->ref_count++;
                send_via_rti_timed(«receivingPortID», «receivingFed.id», message_length, (unsigned char*) «sendRef»->value);
                __done_using(«sendRef»);
            ''')
        } else {
            // Handle native types.
            // string types need to be dealt with specially because they are hidden pointers.
            // void type is odd, but it avoids generating non-standard expression sizeof(void),
            // which some compilers reject.
            var lengthExpression = switch(type.targetType) {
                case 'string': '''strlen(«sendRef») + 1'''
                case 'void': '0'
                default: '''sizeof(«type.targetType»)'''
            }
            var pointerExpression = switch(type.targetType) {
                case 'string': '''(unsigned char*) «sendRef»'''
                default: '''(unsigned char*)&«sendRef»'''
            }
            result.append('''
            size_t message_length = «lengthExpression»;
            send_via_rti_timed(«receivingPortID», «receivingFed.id», message_length, «pointerExpression»);
            ''')
        }
        return result.toString
    }

    /** Generate #include of pqueue.c and either reactor.c or reactor_threaded.c
     *  depending on whether threads are specified in target directive.
     *  As a side effect, this populates the runCommand and compileCommand
     *  private variables if such commands are specified in the target directive.
     */
    override generatePreamble() {
        super.generatePreamble()
        
        pr('#include "core/pqueue.c"')
        pr('#define NUMBER_OF_FEDERATES ' + federates.length);
                        
        // Handle target parameters.
        // First, if there are federates, then ensure that threading is enabled.
        if (targetThreads === 0 && federates.length > 1) {
            targetThreads = 1
        }
        if (targetThreads > 0) {
            // Set this as the default in the generated code,
            // but only if it has not been overridden on the command line.
            pr(startTimers, '''
                if (number_of_threads == 0) {
                   number_of_threads = «targetThreads»;
                }
            ''')
            pr("#include \"core/reactor_threaded.c\"")
        } else {
            pr("#include \"core/reactor.c\"")
        }
        if (federates.length > 1) {
            pr("#include \"core/federate.c\"")
        }
        if (targetFast) {
            // The runCommand has a first entry that is ignored but needed.
            if (runCommand.length === 0) {
                runCommand.add("X")
            }
            runCommand.add("-f")
            runCommand.add("true")
        }
        if (targetKeepalive) {
            // The runCommand has a first entry that is ignored but needed.
            if (runCommand.length === 0) {
                runCommand.add("X")
            }
            runCommand.add("-k")
            runCommand.add("true")
        }
        if (targetTimeout >= 0) {
            // The runCommand has a first entry that is ignored but needed.
            if (runCommand.length === 0) {
                runCommand.add("X")
            }
            runCommand.add("-o")
            runCommand.add(Integer.toString(targetTimeout))
            runCommand.add(targetTimeoutUnit.toString)
        }
        
        // Generate #include statements for each .proto import.
        for (import : resource.allContents.toIterable.filter(Import)) {
            if (import.importURI.endsWith(".proto")) {
                // Strip the ".proto" off the file name.
                // NOTE: This assumes that the filename matches the generated files, which it seems to.
                val rootFilename = import.importURI.substring(0, import.importURI.length - 6)
                // Finally, generate the #include for the generated .h file.
                pr('#include "' + rootFilename + '.pb-c.h"')
            }
        }
    }

    // Regular expression pattern for compiler error messages with resource
    // and line number information. The first match will a resource URI in the
    // form of "file:/path/file.lf". The second match will be a line number.
    // The third match is a character position within the line.
    // The fourth match will be the error message.
    static final Pattern compileErrorPattern = Pattern.compile("^(file:/.*):([0-9]+):([0-9]+):(.*)$");
    
    /** Given a line of text from the output of a compiler, return
     *  an instance of ErrorFileAndLine if the line is recognized as
     *  the first line of an error message. Otherwise, return null.
     *  @param line A line of output from a compiler or other external
     *   tool that might generate errors.
     *  @return If the line is recognized as the start of an error message,
     *   then return a class containing the path to the file on which the
     *   error occurred (or null if there is none), the line number (or the
     *   string "1" if there is none), the character position (or the string
     *   "0" if there is none), and the message (or an empty string if there
     *   is none).
     */
    override parseCommandOutput(String line) {
        val matcher = compileErrorPattern.matcher(line)
        if (matcher.find()) {
            val result = new ErrorFileAndLine()
            result.filepath = matcher.group(1)
            result.line = matcher.group(2)
            result.character = matcher.group(3)
            result.message = matcher.group(4)
            
            if (result.message.toLowerCase.contains("warning:")) {
                result.isError = false
            }
            return result
        }
        return null as ErrorFileAndLine
    }
        
    // //////////////////////////////////////////
    // // Private methods.
    
    /** Return a command to compile the specified C file.
     *  @param fileToCompile The C filename without the .c extension.
     */
    protected def compileCommand(String fileToCompile) {
        val cFilename = fileToCompile + ".c";            
        val relativeSrcFilename = "src-gen" + "/" + cFilename;
        val relativeBinFilename = "bin" + File.separator + fileToCompile;

        var compileCommand = newArrayList
        compileCommand.add(targetCompiler)
        val flags = targetCompilerFlags.split(' ')
        compileCommand.addAll(flags)
        compileCommand.add(relativeSrcFilename)
        if (compileAdditionalSources !== null) {
            compileCommand.addAll(compileAdditionalSources)
        }
        if (compileLibraries !== null) {
            compileCommand.addAll(compileLibraries)
        }
        // Only set the output file name if it hasn't already been set
        // using a target property or command line flag.
        if (compileCommand.forall[it.trim != "-o"]) {
            compileCommand.addAll("-o", relativeBinFilename)
        }

        // If threaded computation is requested, add a -pthread option.
        if (targetThreads !== 0) {
            compileCommand.add("-pthread")
        }
        // If there is no main reactor, then use the -c flag to prevent linking from occurring.
        // FIXME: we could add a `-c` flag to `lfc` to make this explicit in stand-alone mode.
        // Then again, I think this only makes sense when we can do linking.
        // In any case, a warning is helpful to draw attention to the fact that no binary was produced.
        if (main === null) {
            compileCommand.add("-c") // FIXME: revisit
            if (mode === Mode.STANDALONE) {
                reportError("ERROR: Did not output executable; no main reactor found.")
            }
        }
        return compileCommand
    }
    
    /** Perform deferred initializations in initialize_trigger_objects.
     *  @param federate The federate for which we are doing this.
     */
    private def doDeferredInitialize(FederateInstance federate) {
        // First, populate the trigger tables for each output.
        // The entries point to the trigger_t structs for the destination inputs.
        pr('// doDeferredInitialize')
        for (init : deferredInitialize) {
            if (init.reaction === null) {
                // Input port being triggered.
                var triggerStructName = triggerStructName(init.input)
                // If the destination of a connection is an input
                // port of a reactor that has no reactions to that input,
                // then this trigger struct will not have been created.
                // In that case, we want NULL.
                // If the destination is an output port, however, then
                // the dependentReactions.size will be zero, but we nevertheless
                // want to set up the trigger.
                if (init.input.dependentReactions.size === 0 &&
                    !init.input.isOutput) {
                    pr(init.remoteTriggersArrayName + '[' + init.arrayIndex +
                        '] = NULL;')
                } else {
                    pr(
                        init.remoteTriggersArrayName + '[' + init.arrayIndex +
                            '] = &' + triggerStructName + ';')
                }
            } else {
                // Reaction in a container being triggered.
                // In this case, the input field is not an input, but the
                // output of a contained reactor. If the contained reactor
                // is not in the federate, then skip this step.
                // Note that in this case, init.input is misnamed.
                // It is an output.
                if (reactorBelongsToFederate(init.input.parent, federate)) {
                    var triggerStructName = triggerStructName(init.input)
                    pr(
                        init.remoteTriggersArrayName + '[' + init.arrayIndex +
                        '] = &' + triggerStructName + ';')
                }
            }
        }
        // Set all inputs _is_present variables to point to False by default.
        setInputsAbsentByDefault(main, federate)
        
        // For outputs that are not primitive types (of form type* or type[]),
        // create a default token on the self struct.
        createDefaultTokens(main, federate)

        // Next, for every input port, populate its "self" struct
        // fields with pointers to the output port that sends it data.
        connectInputsToOutputs(main, federate)
    }

    /** Generate assignments of pointers in the "self" struct of a destination
     *  port's reactor to the appropriate entries in the "self" struct of the
     *  source reactor.
     *  @param instance The reactor instance.
     *  @param federate The federate for which we are generating code or null
     *   if there is no federation.
     */
    private def void connectInputsToOutputs(ReactorInstance instance, FederateInstance federate) {
        pr('''// Connect inputs and outputs for reactor «instance.getFullName».''')
        for (source : instance.destinations.keySet) {
            // If the source is an input port, find the ultimate source,
            // which could be the input port if it is written to by a reaction
            // or it could be an upstream output port. 
            var eventualSource = sourcePort(source)
            
            // We assume here that all connections across federates have been
            // broken and replaced by reactions handling the communication.
            if (reactorBelongsToFederate(eventualSource.parent, federate)) {
                val destinations = instance.destinations.get(source)
                for (destination : destinations) {
                    var comment = ''
                    if (source !== eventualSource) {
                        comment = ''' (eventual source is «eventualSource.getFullName»)'''
                    }
                    pr('''
                        // Connect «source.getFullName»«comment» to input port «destination.getFullName»
                        «destinationReference(destination, false)» = &«sourceReference(eventualSource, false)»;
                        «destinationReference(destination, true)» = &«sourceReference(eventualSource, true)»;
                    ''')
                }
            }
        }

        for (child : instance.children) {
            // In case this is a composite, recurse.
            connectInputsToOutputs(child, federate)
        }

        // Handle inputs that get sent data from a reaction rather than from
        // another contained reactor and reactions that are triggered by an
        // output of a contained reactor.
        for (reaction : instance.reactions) {
            for (port : reaction.dependentPorts) {
                if (port.definition instanceof Input) {
                    // This reaction is sending to an input. Must be
                    // the input of a contained reactor.
                    // It may be deeply contained, however, in which case
                    // we have to trace back to where the data and is_present
                    // variables are.
                    var sourcePort = sourcePort(port)
                    if (reactorBelongsToFederate(sourcePort.parent, federate)) {
                        pr('''
                            // Connect «sourcePort», which gets data from reaction «reaction.reactionIndex»
                            // of «instance.getFullName», to «port.getFullName».
                            «destinationReference(port, false)» = &«sourceReference(sourcePort, false)»;
                            «destinationReference(port, true)»  = &«sourceReference(sourcePort, true)»;
                        ''')
                    }
                }
            }
            for (port : reaction.dependsOnPorts) {
                if (port.definition instanceof Output) {
                    // This reaction is receiving data from an output
                    // of a contained reactor. If the contained reactor is
                    // not in the federate, then we don't do anything here.
                    if (reactorBelongsToFederate(port.parent, federate)) {
                        pr('''
                            // Record output «port.getFullName», which triggers reaction «reaction.reactionIndex»
                            // of «instance.getFullName», on its self struct.
                            «reactionReference(port, false)» = &«sourceReference(port, false)»;
                            «reactionReference(port, true)» = &«sourceReference(port, true)»;
                        ''')
                    }
                }
            }
        }
        pr('''// END Connect inputs and outputs for reactor «instance.getFullName».''')
    }
    
    /**
     * Given an input port instance, if it receives its data from a reaction somewhere up
     * in the hierarchy, return the port to which the reaction actually writes.
     * The returned port will be this same port if the parent's parent's reaction
     * writes directly to this port, but if this port is deeper in the hierarchy,
     * then this will be a port belonging to highest parent of this port where
     * the parent is contained by the same reactor whose reaction writes to this
     * port.  This method is useful to find the name of the items on the self
     * struct of the reaction's parent that contain the value being sent
     * and its is_present variable.
     * @param port The input port instance.
     */
    private static def PortInstance sourcePort(PortInstance port) {
        // If the port depends on reactions, then this is the port we are looking for.
        if (port.dependsOnReactions.size > 0) return port
        if (port.dependsOnPort === null) return port
        // If we get here, then this port is fed data from another port.
        // Find the source for that port.
        return sourcePort(port.dependsOnPort)
    }

    /** Generate action variables for a reaction.
     *  @param builder The string builder into which to write the code.
     *  @param action The action.
     */
    private def generateActionVariablesInReaction(StringBuilder builder, Action action) {
        // If the action has a type, create variables for accessing the value.
        val type = action.inferredType
        // Pointer to the token_t sent as the payload in the trigger.
        val tokenPointer = '''(self->___«action.name».token)'''
        // Create the _has_value variable.
        pr(builder,
            '''
            bool «action.name»_is_present = self->___«action.name».is_present;
            bool «action.name»_has_value = («tokenPointer» != NULL && «tokenPointer»->value != NULL);
            token_t* «action.name»_token = «tokenPointer»;
            ''')
        // Create the _value variable if there is a type.
        if (!type.isUndefined) {
            if (isTokenType(type)) {
                // Create the value variable, but initialize it only if the pointer is not null.
                // NOTE: The token_t objects will get recycled automatically using
                // this scheme and never freed. The total number of token_t structs created
                // will equal the maximum number of actions that are simultaneously in
                // the event queue.
                
                // If this is an array type, the type cannot be used verbatim; the trailing `[]`
                // should be replaced by a `*`
                var cType = type.targetType
                val matcher = arrayPatternVariable.matcher(cType)
                if (matcher.find()) {
                    cType = matcher.group(1) + '*'
                }
                pr(builder, '''
                    «cType» «action.name»_value;
                    if («action.name»_has_value) {
                        «action.name»_value = ((«cType»)«tokenPointer»->value);
                    }
                    '''
                )
            } else {
                // Create the value variable, but initialize it only if the pointer is not null.
                // NOTE: The token_t objects will get recycled automatically using
                // this scheme and never freed. The total number of token_t structs created
                // will equal the maximum number of actions that are simultaneously in
                // the event queue.
                pr(builder, '''
                    «type.targetType» «action.name»_value;
                    if («action.name»_has_value) {
                        «action.name»_value = *((«type.targetType»*)«tokenPointer»->value);
                    }
                    '''
                )
            }
        }
    }
    
    /** Generate into the specified string builder the code to
     *  initialize local variables for ports in a reaction function
     *  from the "self" struct. The port may be an input of the
     *  reactor or an output of a contained reactor.
     *  @param builder The string builder.
     *  @param trigger The input statement from the AST.
     */
    private def generateInputVariablesInReaction(
        StringBuilder builder,
        Input input
    ) {
        val arraySpec = input.multiportArraySpec
        if (arraySpec != '') {
            pr(builder, '''
                bool «input.name»_is_present«arraySpec»;
            ''')
        } else {
            pr(builder,'''
                bool «input.name»_is_present = *(self->__«input.name»_is_present);
            ''')
        }
        if (input.inferredType.isTokenType) {
            val rootType = input.targetType.rootType
            // Create the name_token variable.
            // If the input is declared mutable, create a writable copy.
            // Note that this will not copy if the reference count is exactly one.
            pr(builder, '''
                «rootType»* «input.name»«arraySpec»;
            ''')
            if (arraySpec == '') {
                pr(builder, '''
                    int «input.name»_length = 0;
                    token_t* «input.name»_token = *(self->__«input.name»);
                    if («input.name»_is_present) {
                        «input.name»_length = (*(self->__«input.name»))->length;
                        «IF input.isMutable»
                            «input.name»_token = writable_copy(*(self->__«input.name»));
                            «input.name» = («rootType»*)(«input.name»_token->value);
                        «ELSE»
                            «input.name» = («rootType»*)((*(self->__«input.name»))->value);
                        «ENDIF»
                    }
                ''')
            } else {
                // FIXME: Here the multiport width is a property of the class definition,
                // which means it cannot be parameterized. Perhaps the width should be
                // a field on the self struct.
                pr(builder, '''
                    int «input.name»_length«arraySpec»;
                    token_t* «input.name»_token«arraySpec»;
                    // FIXME: Here the multiport width is a property of the class definition,
                    // which means it cannot be parameterized. Perhaps the width should be
                    // a field on the self struct.
                    for (int i = 0; i < «input.multiportWidth»; i++) {
                        «input.name»_length[i] = 0
                        «input.name»_token[i] = *(self->__«input.name»[i]);
                        if («input.name»_is_present[i]) {
                            «input.name»_length[i] = (*(self->__«input.name»[i]))->length;
                            «IF input.isMutable»
                                «input.name»_token[i] = writable_copy(*(self->__«input.name»[i]));
                                «input.name»[i] = («rootType»*)(«input.name»_token[i]->value);
                            «ELSE»
                                «input.name»[i] = («rootType»*)((*(self->__«input.name»[i]))->value);
                            «ENDIF»
                        }
                    }
                    int «input.name»_width = «input.multiportWidth»;
                ''')
            }
        } else if (input.type !== null) {
            // Look for array type of form type[number].
            val matcher = arrayPatternFixed.matcher(input.type.targetType)
            if (matcher.find) {
                pr(builder, '''«matcher.group(1)»* «input.name»«arraySpec»;''')
            } else {
                pr(builder, '''«input.type.targetType» «input.name»«arraySpec»;''')
            }
            if (arraySpec == '') {
                pr(builder, '''
                    if («input.name»_is_present) {
            	       «input.name» = *(self->__«input.name»);
                    }
                ''')
            } else {
                pr(builder, '''
                    for (int i = 0; i < «input.multiportWidth»; i++) {
                        «input.name»_is_present[i] = *(self->__«input.name»_is_present[i]);
                        if («input.name»_is_present[i]) {
                            «input.name»[i] = *(self->__«input.name»[i]);
                        }
                    }
                    int «input.name»_width = «input.multiportWidth»;
                ''')
            }
        }
    }
    /** Generate into the specified string builder the code to
     *  initialize local variables for ports in a reaction function
     *  from the "self" struct. The port may be an input of the
     *  reactor or an output of a contained reactor.
     *  @param builder The string builder.
     *  @param trigger The input statement from the AST.
     */
    private def generatePortVariablesInReaction(
        StringBuilder builder,
        HashMap<Instantiation,StringBuilder> structs,
        VarRef port
    ) {
        if (port.variable instanceof Input) {
            generateInputVariablesInReaction(builder, port.variable as Input)
        } else {
            // port is an output of a contained reactor.
            val output = port.variable as Output
            val portName = output.name
            val portType = lfTypeToTokenType(output.inferredType)
            
            var structBuilder = structs.get(port.container)
            if (structBuilder === null) {
                structBuilder = new StringBuilder
                structs.put(port.container, structBuilder)
            }
            val reactorName = port.container.name
            // First define the struct containing the output value and indicator
            // of its presence.
            pr(structBuilder, portType + ' ' + portName + '; ')
            pr(structBuilder, 'bool ' + portName + '_is_present;')

            // Next, initialize the struct with the current values.
            pr(
                builder,
                reactorName + '.' + portName + ' = *(self->__' + reactorName +
                    '.' + portName + ');'
            )
            pr(
                builder,
                reactorName + '.' + portName + '_is_present = *(self->__' +
                    reactorName + '.' + portName + '_is_present);'
            )
        }
    }

    /** Generate into the specified string builder the code to
     *  initialize local variables for outputs in a reaction function
     *  from the "self" struct.
     *  @param builder The string builder.
     *  @param output The output statement from the AST.
     */
    private def generateOutputVariablesInReaction(
        StringBuilder builder,
        Output output
    ) {
        if (output.type === null) {
            reportError(output,
                "Output is required to have a type: " + output.name)
        } else {
            val outputType = lfTypeToTokenType(output.inferredType)
            // Define a variable of type 'type*' with name matching the output name.
            // If the output type has the form type[number],
            // then the variable is set equal to the pointer in the self struct
            // to the output value. Otherwise, if the output type has the form
            // type[], or type*, the variable is set to NULL.
            // Otherwise, it is set to the _address_ of the
            // entry in the self struct corresponding to the output.  
            val matcher = arrayPatternFixed.matcher(outputType)
            if (matcher.find()) {
                pr(
                    builder,
                    rootType(output.targetType) + '* ' + output.name +
                        ' = self->__' + output.name + ';'
                )
            } else if (isTokenType(output.inferredType)) {
                pr(
                    builder,
                    rootType(output.targetType) + '* ' + output.name + ' = NULL;'
                )
            } else {
                pr(
                    builder,
                    outputType + '* ' + output.name +
                        ' = &(self->__' + output.name + ');'
                )
            }
            // Also define a boolean variable name_is_present with value
            // equal to the current value of the corresponding is_present field
            // in the self struct. This can be used to test whether a previous
            // reaction has already set an output value at the current logical time.
            pr(builder, 'bool ' + output.name + '_is_present = self->__'
                + output.name + '_is_present;'
            )
        }
    }

    /** Generate into the specified string builder the code to
     *  initialize local variables for sending data to an input
     *  of a contained reaction (e.g. for a deadline violation).
     *  The code goes into two builders because some of it has to
     *  collected into a single struct definition.
     *  @param builder The string builder.
     *  @param definition AST node defining the reactor within which this occurs
     *  @param input Input of the contained reactor.
     */
    private def generateVariablesForSendingToContainedReactors(
        StringBuilder builder,
        HashMap<Instantiation,StringBuilder> structs,
        Instantiation definition,
        Input input
    ) {
        var structBuilder = structs.get(definition)
        if (structBuilder === null) {
            structBuilder = new StringBuilder
            structs.put(definition, structBuilder)
        }
        pr(structBuilder, lfTypeToTokenType(input.inferredType) + '* ' + input.name + ';')
        pr(structBuilder, ' bool ' + input.name + '_is_present;')        
        
        pr(builder,
            definition.name + '.' + input.name + ' = &(self->__' +
            definition.name + '.' + input.name + ');'
        )
        pr(builder,
            definition.name + '.' + input.name + '_is_present = self->__' +
            definition.name + '.' + input.name + '_is_present;'
        )
    }

    /** Return a C type for the type of the specified parameter.
     *  If there are code delimiters around it, those are removed.
     *  If the type is "time", then it is converted to "interval_t".
     *  If the type is of the form "type[]", then this is converted
     *  to "type*".
     *  @param parameter The parameter.
     *  @return The C type.
     */
    private def getParameterType(Parameter parameter) {
        var type = parameter.targetType
        val matcher = arrayPatternVariable.matcher(type)
        if (matcher.find()) {
            return matcher.group(1) + '*'
        }
        type
    }
    
    /** Return a C type for the type of the specified state variable.
     *  If there are code delimiters around it, those are removed.
     *  If the type is "time", then it is converted to "interval_t".
     *  If the type is of the form "type[]", then this is converted
     *  to "type*".
     *  @param state The state variable.
     *  @return The C type.
     */
    private def getStateType(StateVar state) {
        // A state variable may directly refer to its initializing parameter,
        // in which case, it inherits the type from the parameter.
//        if (state.init !== null && state.init.size == 1) {
//            val parm = state.init.get(0).parameter
//            if (parm !== null)
//                return parm.type.toText
//        }
//        if (state.ofTimeType) {
//            return timeTypeInTargetLanguage
//        }
//        if (state.type === null || state.type.toText.equals("")) {
//            reportError(state,
//                "State is required to have a type: " + state.name)
//            return "(ERROR: NO TYPE)"
//        }
//        var type = state.type.toText
//        if (state.isOfTimeType) {
//            type = 'interval_t'
//        } else {
//            val matcher = arrayPatternVariable.matcher(type)
//            if (matcher.find()) {
//                return matcher.group(1) + '*'
//            }
//        }
//        type

        var type = state.getInferredType.targetType
        val matcher = arrayPatternVariable.matcher(type)
        if (matcher.find()) {
            return matcher.group(1) + '*'
        }
        type
    }
    
    /** Given a type for an input or output, return true if it should be
     *  carried by a token_t struct rather than the type itself.
     *  It should be carried by such a struct if the type ends with *
     *  (it is a pointer) or [] (it is a array with unspecified length).
     *  @param type The type specification.
     */
    private def isTokenType(InferredType type) {
        if (type.isUndefined)
            return false
        val targetType = type.targetType
        if (targetType.trim.matches("^\\w*\\[\\s*\\]$") || targetType.trim.endsWith('*')) {
            true
        } else {
            false
        }
    }
    
    /** If the type specification of the form type[] or
     *  type*, return the type. Otherwise remove the code delimiter,
     *  if there is one, and otherwise just return the argument
     *  unmodified.
     *  @param type A string describing the type.
     */
    private def rootType(String type) {
        if (type.endsWith(']')) {
            val root = type.indexOf('[')
            type.substring(0, root).trim
        } else if (type.endsWith('*')) {
            type.substring(0, type.length - 1).trim
        } else {
            type.trim
        }
    }

    /** Convert a type specification of the form type[], type[num]
     *  or type* to token_t*. Otherwise, remove the code delimiter,
     *  if there is one, and otherwise just return the argument
     *  unmodified.
     */
    private def lfTypeToTokenType(InferredType type) {
        var result = type.targetType
        if (isTokenType(type)) {
            result = 'token_t*'
        }
        result
    }

    /** Print the #line compiler directive with the line number of
     *  the specified object.
     *  @param output Where to put the output.
     *  @param eObject The node.
     */
    protected def prSourceLineNumber(StringBuilder output, EObject eObject) {
        var node = NodeModelUtils.getNode(eObject)
        if (node !== null) {
            // For code blocks (delimited by {= ... =}, unfortunately,
            // we have to adjust the offset by the number of newlines before {=.
            // Unfortunately, this is complicated because the code has been
            // tokenized.
            var offset = 0
            if (eObject instanceof Code) {
                offset += 1
            }
            if (System.getProperty("os.name").toLowerCase.contains("windows")) {
                pr(output, "#line " + (node.getStartLine() + offset) + ' "file:' + windowsSourceFile + '"')
            } else {
                pr(output, "#line " + (node.getStartLine() + offset) + ' "file:' + sourceFile + '"')
            }
        }
    }

    /** Print the #line compiler directive with the line number of
     *  the specified object.
     *  @param eObject The node.
     */
    protected def prSourceLineNumber(EObject eObject) {
        prSourceLineNumber(code, eObject)
    }

    /**
     * Version of pr() that prints a source line number using a #line
     * prior to each line of the output. Use this when multiple lines of
     * output code are all due to the same source line in the .lf file.
     * @param eObject The AST node that this source line is based on.
     * @param builder The code buffer.
     * @param text The text to append.
     */
    protected def pr(EObject eObject, StringBuilder builder, Object text) {
        var split = text.toString.split("\n")
        for (line : split) {
            prSourceLineNumber(builder, eObject)
            pr(builder, line)
        }
    }

    /** For each output that has a token type (type* or type[]),
     *  create a default token and put it on the self struct.
     *  @param parent The container reactor.
     *  @param federate The federate, or null if there is no federation.
     */
    private def void createDefaultTokens(ReactorInstance parent, FederateInstance federate) {
        for (containedReactor : parent.children) {
            // Do this only for reactors in the federate.
            if (reactorBelongsToFederate(containedReactor, federate)) {
                var nameOfSelfStruct = selfStructName(containedReactor)
                for (output : containedReactor.outputs) {
                    val type = (output.definition as Output).inferredType
                    if (type.isTokenType) {
                        // Create the template token that goes in the trigger struct.
                        // Its reference count is zero, enabling it to be used immediately.
                        var rootType = type.targetType.rootType
                        // If the rootType is 'void', we need to avoid generating the code
                        // 'sizeof(void)', which some compilers reject.
                        val size = (rootType == 'void') ? '0' : '''sizeof(«rootType»)'''
                        pr('''
                            «nameOfSelfStruct»->__«output.name» = __create_token(«size»);
                        ''')
                    }
                }
                // In case this is a composite, handle its contained reactors.
                createDefaultTokens(containedReactor, federate)
            }
        }
    }
    
    /** Set inputs _is_present variables to the default false.
     *  This is useful in case the input is left unconnected.
     *  @param parent The container reactor.
     *  @param federate The federate, or null if there is no federation.
     */
    private def void setInputsAbsentByDefault(ReactorInstance parent, FederateInstance federate) {
        // For all inputs, set a default where their _is_present variable points to False.
        // This handles dangling input ports that are not connected to anything
        // even if they are connected locally in the hierarchy, but not globally.
        for (containedReactor : parent.children) {
            // Do this only for reactors in the federate.
            if (reactorBelongsToFederate(containedReactor, federate)) {
                var selfStructName = selfStructName(containedReactor)
                for (input : containedReactor.inputs) {
                    val width = input.definition.multiportWidth
                    if (width > 0) {
                        pr('''
                            for (int i = 0; i < «width»; i++) {
                                «selfStructName»->__«input.definition.name»_is_present[i] = &absent;
                            }
                        ''')
                    } else {
                        pr('''«selfStructName»->__«input.definition.name»_is_present = &absent;''')                        
                    }
                }
                // In case this is a composite, handle its assignments.
                setInputsAbsentByDefault(containedReactor, federate)
            }
        }
    }
        
    // Regular expression pattern for array types with specified length.
    // \s is whitespace, \w is a word character (letter, number, or underscore).
    // For example, for "foo[10]", the first match will be "foo" and the second "[10]".
    static final Pattern arrayPatternFixed = Pattern.compile("^\\s*+(\\w+)\\s*(\\[[0-9]+\\])\\s*$");
    
    // Regular expression pattern for array types with unspecified length.
    // \s is whitespace, \w is a word character (letter, number, or underscore).
    // For example, for "foo[]", the first match will be "foo".
    static final Pattern arrayPatternVariable = Pattern.compile("^\\s*+(\\w+)\\s*\\[\\]\\s*$");
    
    static var DISABLE_REACTION_INITIALIZATION_MARKER
        = '// **** Do not include initialization code in this reaction.'
        
    public static var DEFAULT_MIN_INTER_ARRIVAL = new TimeValue(1, TimeUnit.NSEC)
        
    override getTargetTimeType() '''interval_t'''

    override getTargetUndefinedType() '''/* «reportError("undefined type")» */'''

    override getTargetFixedSizeListType(String baseType,
        Integer size) '''«baseType»[«size»]'''
        
    override String getTargetVariableSizeListType(
        String baseType) '''«baseType»[]'''
    
    protected def String getInitializer(ParameterInstance p) {
        
            if (p.type.isList && p.init.size > 1) {
                return p.init.join('{', ', ', '}', [it.targetValue])
            } else {
            	return p.init.get(0).targetValue
            }
        
    }
    
    override supportsGenerics() {
        return false
    }
    
    override generateDelayGeneric() {
        throw new UnsupportedOperationException("TODO: auto-generated method stub")
    }
    
}
