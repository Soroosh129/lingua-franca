/* Generator for TypeScript target. */

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
import java.util.HashMap
import java.util.HashSet
import java.util.LinkedList
import java.util.List
import java.util.StringJoiner
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext
import org.icyphy.Targets.LoggingLevels
import org.icyphy.TimeValue
import org.icyphy.linguaFranca.Action
import org.icyphy.linguaFranca.Input
import org.icyphy.linguaFranca.Instantiation
import org.icyphy.linguaFranca.Parameter
import org.icyphy.linguaFranca.Port
import org.icyphy.linguaFranca.Reactor
import org.icyphy.linguaFranca.StateVar
import org.icyphy.linguaFranca.TimeUnit
import org.icyphy.linguaFranca.Timer
import org.icyphy.linguaFranca.VarRef
import org.icyphy.linguaFranca.Variable

import static extension org.icyphy.ASTUtils.*

// FIXME: This still has a bunch of copied code from CGenerator that should be removed.

/** Generator for TypeScript target.
 *
 *  @author{Matt Weber <matt.weber@berkeley.edu>}
 *  @author{Edward A. Lee <eal@berkeley.edu>}
 *  @author{Marten Lohstroh <marten@berkeley.edu>}
 *  @author {Christian Menard <christian.menard@tu-dresden.de> 
 */
class TypeScriptGenerator extends GeneratorBase {

    // Set of acceptable import targets includes only TypeScript.
    val acceptableTargetSet = newHashSet('TypeScript')
    
    // Target filename.
    var tsFilename = filename + ".ts"
    var jsFilename = filename + ".js"
    var configPath = File.separator + "lib" + File.separator + "TS"
    var projectPath = directory + File.separator + filename
    var reactorTSPath = File.separator + "lib" + File.separator +
        "TS" + File.separator + "reactor-ts"
    var srcGenPath = projectPath + File.separator + "src"
    var outPath = projectPath + File.separator + "dist"
    var reactorTSCorePath = reactorTSPath + File.separator + "src" + File.separator
        + "core" + File.separator
    var tscPath = directory + File.separator + "node_modules" +  File.separator 
        + "typescript" +  File.separator + "bin" +  File.separator + "tsc"
    
    
    // List of validly typed parameters of the main reactor for 
    // custom command line arguments
    var customCLArgs = new HashSet<Parameter>()

    /** Generate TypeScript code from the Lingua Franca model contained by the
     *  specified resource. This is the main entry point for code
     *  generation.
     *  @param resource The resource containing the source code.
     *  @param fsa The file system access (used to write the result).
     *  @param context FIXME: Undocumented argument. No idea what this is.
     */
    override void doGenerate(
        Resource resource,
        IFileSystemAccess2 fsa,
        IGeneratorContext context
    ) {        
        super.doGenerate(resource, fsa, context)
        
        // Generate code for each reactor. 
        for (r : reactors) {
            r.generateReactor()
        }
        
        // Important files and directories
        tsFilename = filename + ".ts"
        jsFilename = filename + ".js"
        projectPath = directory + File.separator + filename
        reactorTSPath = File.separator + "lib" + File.separator +
            "TS" + File.separator + "reactor-ts"
        srcGenPath = projectPath + File.separator + "src"
        outPath = projectPath + File.separator + "dist"
        reactorTSCorePath = reactorTSPath + File.separator + "src" + File.separator
            + "core" + File.separator
        tscPath = directory + File.separator + "node_modules" +  File.separator 
        + "typescript" +  File.separator + "bin" +  File.separator + "tsc"
        
        // Generate main instance, if there is one.
        if (this.mainDef !== null) {
            generateReactor(this.mainDef.reactorClass)
            generateReactorInstance(this.mainDef)
            generateRuntimeStart(this.mainDef)
        }
        
        // Create output directories if they don't yet exist
        var dir = new File(projectPath)
        if (!dir.exists()) dir.mkdirs()
        dir = new File(srcGenPath)
        if (!dir.exists()) dir.mkdirs()
        dir = new File(outPath)
        if (!dir.exists()) dir.mkdirs()

        // Delete source previously output the LF compiler
        var file = new File(srcGenPath + File.separator + tsFilename)
        if (file.exists) {
            file.delete
        }

        // Delete .js previously output by TypeScript compiler
        file = new File(outPath + File.separator + jsFilename)
        if (file.exists) {
            file.delete
        }

        // Write the generated code to the srcGen directory.
        var fOut = new FileOutputStream(
            new File(srcGenPath + File.separator + tsFilename));
        fOut.write(getCode().getBytes())
        
        // Copy the required library files into the src directory
        // so they may be compiled as part of the TypeScript project.
        // This requires that the TypeScript submodule has been installed.
        copyReactorTSCoreFile(srcGenPath, "reactor.ts")
        copyReactorTSCoreFile(srcGenPath, "cli.ts")
        copyReactorTSCoreFile(srcGenPath, "command-line-args.d.ts")
        copyReactorTSCoreFile(srcGenPath, "command-line-usage.d.ts")
        copyReactorTSCoreFile(srcGenPath, "microtime.d.ts")
        copyReactorTSCoreFile(srcGenPath, "nanotimer.d.ts")
        copyReactorTSCoreFile(srcGenPath, "time.ts")
        copyReactorTSCoreFile(srcGenPath, "ulog.d.ts")
        copyReactorTSCoreFile(srcGenPath, "util.ts")
        
        // Only run npm install if we had to copy over the defaul package.json.
        var boolean runNpmInstall
        var File packageJSONFile = new File(directory + File.separator + "package.json")
        if (packageJSONFile.exists()) {
            runNpmInstall = false
        } else {
            runNpmInstall = true
        }

        // Copy default versions of config files into project if
        // they don't exist.       
        createDefaultConfigFile(directory, "package.json")
        createDefaultConfigFile(projectPath, "tsconfig.json")
        createDefaultConfigFile(projectPath, "babel.config.js")
        
        // NOTE: (IMPORTANT) at least on my mac, the instance of eclipse running this program did not have
        // the complete PATH variable needed to find the command npm. I had
        // to start my eclipse instance from a terminal so eclipse would have the correct environment
        // variables to run this command. Now, executeCommand makes a second
        // attempt to run the command using a bash shell, so if you have a
        // ~/.bash_profile file that specifies suitable paths, the command should
        // work.
        
        // Install npm modules only if the default package.json was copied over.
        
        if (runNpmInstall) {
            var installCmd = newArrayList();
            installCmd.addAll("npm", "install")
            
            if (executeCommand(installCmd, directory) !== 0) {
                reportError(resource.findTarget, "ERROR: npm install command failed."
                    + "\nFor installation instructions, see: https://www.npmjs.com/get-npm")
                return
            }
        }
        
        refreshProject()

        // Invoke the compiler on the generated code.
//        val relativeSrcFilename = "src-gen" + File.separator + tsFilename;
//        val relativeTSFilename = "ts" + File.separator + filename + '.js';
        
        // Working example: src-gen/Minimal.ts --outDir bin --module CommonJS --target es2018 --esModuleInterop true --lib esnext,dom --alwaysStrict true --strictBindCallApply true --strictNullChecks true
        // Must compile to ES2015 or later and include the dom library.
        // Working command without a tsconfig.json:
        // compileCommand.addAll(tscPath,  relativeSrcFilename, 
        //      "--outDir", "js", "--module", "CommonJS", "--target", "es2018", "--esModuleInterop", "true",
        //      "--lib", "esnext,dom", "--alwaysStrict", "true", "--strictBindCallApply", "true",
        //      "--strictNullChecks", "true");
        
        // FIXME: Perhaps add a compileCommand option to the target directive, as in C.
        // Here, we just use a generic compile command.
        var typeCheckCommand = newArrayList()

        // If $tsc is run with no arguments, it uses the tsconfig file.
        typeCheckCommand.addAll(tscPath)
        
        println("Type checking with command: " + typeCheckCommand.join(" "))
        if (executeCommand(typeCheckCommand, projectPath) != 0) {
            reportError("Type checking failed.")
        } else {
            // Babel will compile TypeScript to JS even if there are type errors
            // so only run compilation if tsc found no problems.
            var babelPath = directory + File.separator + "node_modules" + File.separator + ".bin" + File.separator + "babel"
            // Working command  $./node_modules/.bin/babel src-gen --out-dir js --extensions '.ts,.tsx'
            var compileCommand = newArrayList(babelPath, "src",
                "--out-dir", "dist", "--extensions", ".ts")
            println("Compiling with command: " + compileCommand.join(" "))
            if (executeCommand(compileCommand, projectPath) !== 0) {
                reportError("Compiler failed.")
            } else {
                println("SUCCESS (compiling generated TypeScript code)")
            }
        }
    }
    
    override generateDelayBody(Action action, VarRef port) {
        '''actions.«action.name».schedule(0, «generateVarRef(port)» as «getActionType(action)»);'''
    }

    override generateForwardBody(Action action, VarRef port) {
        '''«generateVarRef(port)» = «action.name» as «getActionType(action)»;'''
    }
 
    override String getTargetReference(Parameter param) {
        return '''this.«param.name».get()'''
    }
 
    // //////////////////////////////////////////
    // // Code generators.
    /** Generate a reactor class definition.
     *  @param reactor The parsed reactor data structure.
     */
    def generateReactor(Reactor reactor) {

        var reactorConstructor = new StringBuilder()

        pr("// =============== START reactor class " + reactor.name)

        for (p : reactor.preambles ?: emptyList) {
            pr("// *********** From the preamble, verbatim:")
            pr(p.code.toText)
            pr("\n// *********** End of preamble.")
        }
        
        val reactorName = reactor.name + reactor.typeParms?.join('<', ',', '>', [it.toText])
        // NOTE: type parameters that are referenced in ports or actions must extend
        // Present in order for the program to type check.
        if(reactor.isMain()){
            pr("export class " + reactorName + " extends App {")
        } else {
            pr("export class " + reactorName + " extends Reactor {")
        }
        
        indent()
        
        var arguments = new LinkedList()
        if (reactor.isMain()) {
            //arguments.add("name: string")
            arguments.add("timeout: TimeValue | undefined = undefined")
            arguments.add("keepAlive: boolean = false")
            arguments.add("fast: boolean = false")
        } else {
            arguments.add("parent:Reactor")
        }
        
        // For TS, parameters are arguments of the class constructor.
        for (parameter : reactor.parameters) {
            arguments.add(parameter.initializeParameter)
        }
        
        if (reactor.isMain()) {
            
            arguments.add("success?: () => void")
            arguments.add("fail?: () => void")
            pr(reactorConstructor, "constructor (")
            reactorConstructor.indent
            pr(reactorConstructor, arguments.join(', \n'))
            reactorConstructor.unindent
            pr(reactorConstructor, ") {")
            reactorConstructor.indent
            pr(reactorConstructor, "super(timeout, keepAlive, fast, success, fail);");
        } else {
            pr(reactorConstructor, "constructor (")
            reactorConstructor.indent
            pr(reactorConstructor, arguments.join(', \n'))
            reactorConstructor.unindent
            pr(reactorConstructor, ") {")
            reactorConstructor.indent()
            pr(reactorConstructor, "super(parent);");
        }
        
        // Next handle child reactors instantiations
        for (childReactor : reactor.instantiations ) {
            pr(childReactor.getName() + ": " + childReactor.reactorClass.name + childReactor.typeParms.join('<', ',', '>', [it | it.toText]))
            
            var childReactorArguments = new StringJoiner(", ");
            childReactorArguments.add("this")
        
            // Iterate through parameters in the order they appear in the
            // reactor class, find the matching parameter assignments in
            // the reactor instance, and write the corresponding parameter
            // value as an argument for the TypeScript constructor
            for (parameter : childReactor.reactorClass.parameters) {
                childReactorArguments.add(parameter.getTargetInitializer(childReactor))
            }
            
            pr(reactorConstructor, "this." + childReactor.getName()
                + " = new " + childReactor.reactorClass.name + 
                "(" + childReactorArguments + ")" )
        }
       
        
        // Next handle timers.
        for (timer : reactor.timers) {
            
            var String timerPeriod
            if (timer.period === null) {
                timerPeriod = "0";
            } else {
                timerPeriod = timer.period.targetValue
            }
            
            var String timerOffset
            if (timer.offset === null) {
                timerOffset = "0";
            } else {

                timerOffset = timer.offset.targetValue

            }

            pr(timer.getName() + ": Timer;")
            pr(reactorConstructor, "this." + timer.getName()
                + " = new Timer(this, " + timerOffset + ", "+ timerPeriod + ");")
            
        }     

        // Create properties for parameters
        for (param : reactor.parameters) {
            pr(param.name + ": Parameter<" + param.targetType + ">;")
            pr(reactorConstructor, "this." + param.name +
                " = new Parameter(" + param.name + ");" )
        }

        // Next handle states.
        for (stateVar : reactor.stateVars) {
            if (stateVar.isInitialized) {
                pr(reactorConstructor, "this." + stateVar.name + ' = ' + 
                    "new State(" + stateVar.targetInitializer + ');');
            } else {
            	pr(reactorConstructor, "this." + stateVar.name + ' = ' + 
                    "new State(undefined);");
            }
        }
        
        for (stateVar : reactor.stateVars) {            
            pr(stateVar.name + ': ' + "State<" + stateVar.getTargetType + '>;');            
        }
        // Next handle actions.
        for (action : reactor.actions) {
            // Shutdown actions are handled internally by the
            // TypeScript reactor framework. There would be a
            // duplicate action if we included the one generated
            // by LF.
            if (action.name != "shutdown") {
                pr(action.name + ": Action<" + getActionType(action) + ">;")

                var actionArgs = "this, Origin." + action.origin  
                if (action.minDelay !== null) {
                    // Actions in the TypeScript target are constructed
                    // with an optional minDelay argument which defaults to 0.
                    if (action.minDelay.parameter !== null) {
                        actionArgs+= ", " + action.minDelay.parameter.name
                    } else {
                        actionArgs+= ", " + action.minDelay.targetValue    
                    }
                }
                pr(reactorConstructor, "this." + 
                    action.name + " = new Action<" + getActionType(action) +
                    ">(" + actionArgs  + ");")
            }
        }
        
        // Next handle inputs.
        for (input : reactor.inputs) {
            pr(input.name + ": " + "InPort<" + getPortType(input) + ">;")
            pr(reactorConstructor, "this." + input.name + " = new InPort<"
                + getPortType(input) + ">(this);")
        }
        
        // Next handle outputs.
        for (output : reactor.outputs) {
            pr(output.name + ": " + "OutPort<" + getPortType(output) + ">;")
            pr(reactorConstructor, "this." + output.name + " = new OutPort<"
                + getPortType(output) + ">(this);")
        }
        
        // Next handle connections
        for (connection : reactor.connections) {
            var leftPortName = ""
            if (connection.leftPort.container !== null) {
                leftPortName += connection.leftPort.container.name + "."
            }
            leftPortName += connection.leftPort.variable.name 
            
            var rightPortName = ""
            if (connection.rightPort.container !== null) {
                rightPortName += connection.rightPort.container.name + "."
            }
            rightPortName += connection.rightPort.variable.name 
            
            pr(reactorConstructor, "this._connect(this." + leftPortName + ", this." + rightPortName + ");")
        }
        
        
        // Next handle reaction instances
        for (reaction : reactor.reactions) {
            
            // Determine signature of the react function
            var reactSignature = new StringJoiner(", ")
            reactSignature.add("this")
            
            // The prologue to the react function writes state
            // and parameters to local variables of the same name
            var reactPrologue = new StringBuilder()
            pr(reactPrologue, "const util = this.util;")
            
            // The epilogue to the react function writes local
            // state variables back to the state
            var reactEpilogue = new StringBuilder()
            
            // Assemble react function arguments from sources and effects
            // Arguments are either elements of this reactor, or an object
            // representing a contained reactor with properties corresponding
            // to listed sources and effects.
            
            // If a source or effect is an element of this reactor, add it
            // directly to the reactFunctArgs string. If it isn't, write it 
            // into the containerToArgs map, and add it to the string later.
            var reactFunctArgs = new StringJoiner(", ")
            // Combine triggers and sources into a set
            // so we can iterate over their union
            var triggersUnionSources = new HashSet<VarRef>()
            for (trigger : reaction.triggers) {
                if (!(trigger.startup || trigger.shutdown)) {
                    triggersUnionSources.add(trigger as VarRef)
                }
            }
            for (source : reaction.sources) {
                triggersUnionSources.add(source)
            }
            
            // Create a set of effect names so actions that appear
            // as both triggers/sources and effects can be
            // identified and added to the reaction arguments once.
            // We can't create a set of VarRefs because
            // an effect and a trigger/source with the same name are
            // unequal. 
            // The key of the pair is the effect's container's name,
            // The effect of the pair is the effect's name
            var effectSet = new HashSet<Pair<String, String>>()

            for (effect : reaction.effects) {
                var key = ""; // The container, defaults to an empty string
                var value = effect.variable.name; // The name of the effect
                if (effect.container !== null) {
                    key = effect.container.name
                }
                effectSet.add(new Pair(key, value))
            }

            // Add triggers and sources to the react function
            var containerToArgs = new HashMap<Instantiation, HashSet<Variable>>();           
            for (trigOrSource : triggersUnionSources) {
                // Actions that are both read and scheduled should only
                // appear once as a schedulable effect
                
                var trigOrSourceKey = "" // The default for no container
                var trigOrSourceValue = trigOrSource.variable.name
                if (trigOrSource.container !== null) {
                    trigOrSourceKey = trigOrSource.container.name
                }
                var trigOrSourcePair = new Pair(trigOrSourceKey, trigOrSourceValue)
                 
                if (!effectSet.contains(trigOrSourcePair)) {
                    var reactSignatureElementType = "";
                    
                    if (trigOrSource.variable instanceof Timer) {
                        reactSignatureElementType = "Tag"
                    } else if (trigOrSource.variable instanceof Action) {
                        reactSignatureElementType = getActionType(trigOrSource.variable as Action)
                    } else if (trigOrSource.variable instanceof Port) {
                        reactSignatureElementType = getPortType(trigOrSource.variable as Port)
                    }
                    
                    reactSignature.add('''«trigOrSource.generateArg»: Read<«reactSignatureElementType»>''')
                    reactFunctArgs.add("this." + trigOrSource.generateVarRef)
                    if (trigOrSource.container === null) {
                        pr(reactPrologue, '''let «trigOrSource.variable.name» = «trigOrSource.generateArg».get();''')
                    } else {
                        var args = containerToArgs.get(trigOrSource.container)
                        if (args === null) {
                           // Create the HashSet for the container
                           // and handle it later.
                           args = new HashSet<Variable>();
                           containerToArgs.put(trigOrSource.container, args)
                        }
                        args.add(trigOrSource.variable)
                    }
                }
            }
            var schedActionSet = new HashSet<Action>();
            for (effect : reaction.effects) {
                var functArg = ""                
                var reactSignatureElement = "" + effect.generateArg
                if (effect.variable instanceof Timer) {
                    reportError("A timer cannot be an effect of a reaction")
                } else if (effect.variable instanceof Action){
                    reactSignatureElement += ": Schedule<" + getActionType(effect.variable as Action) + ">"
                    schedActionSet.add(effect.variable as Action)
                } else if (effect.variable instanceof Port){
                    reactSignatureElement += ": ReadWrite<" + getPortType(effect.variable as Port) + ">"
                    if (effect.container === null) {
                        pr(reactEpilogue, "if (" + effect.variable.name + " !== undefined) {")
                        reactEpilogue.indent()
                        pr(reactEpilogue,  "__" + effect.variable.name + ".set(" + effect.variable.name + ");")
                        reactEpilogue.unindent()
                        pr(reactEpilogue, "}")   
                    }
                }

                reactSignature.add(reactSignatureElement)
                
                functArg = "this." + effect.generateVarRef 
                if (effect.variable instanceof Action){
                    reactFunctArgs.add("this.schedulable(" + functArg + ")")
                } else if (effect.variable instanceof Port) {
                    reactFunctArgs.add("this.writable(" + functArg + ")")
                }  
                
                if (effect.container === null) {
                    pr(reactPrologue, "let " + effect.variable.name + " = __" + effect.variable.name + ".get();")
                } else {
                    // Hierarchical references are handled later because there
                    // could be references to other members of the same reactor.
                    var args = containerToArgs.get(effect.container)
                    if (args === null) {
                       args = new HashSet<Variable>();
                       containerToArgs.put(effect.container, args)
                    }
                    args.add(effect.variable)
                }
            }
            
            // Iterate through the actions to handle the prologue's
            // "actions" object
            var prologueActionObjectBody = new StringJoiner(", ")
            for (act : schedActionSet) {
                prologueActionObjectBody.add(act.name + ": __" + act.name)
            }
            if (schedActionSet.size > 0) {
                pr(reactPrologue, "let actions = {"
                    + prologueActionObjectBody + "};")
            }
            
            // Add parameters to the react function
            for (param : reactor.parameters) {
                
                // Underscores are added to parameter names to prevent conflict with prologue
                reactSignature.add("__" + param.name + ": Parameter<"
                    + param.targetType + ">")
                reactFunctArgs.add("this." + param.name)
                
                pr(reactPrologue, "let " + param.name + " = __" + param.name + ".get();")
            }
            
            // Add state to the react function
            for (state : reactor.stateVars) {
                // Underscores are added to state names to prevent conflict with prologue
                reactSignature.add("__" + state.name + ": State<"
                    + getStateType(state) + ">")
                reactFunctArgs.add("this." + state.name )
                
                pr(reactPrologue, "let " + state.name + " = __" + state.name + ".get();")
                pr(reactEpilogue, "if (" + state.name + " !== undefined) {")
                reactEpilogue.indent()
                pr(reactEpilogue,  "__" + state.name + ".set(" + state.name + ");")
                reactEpilogue.unindent()
                pr(reactEpilogue, "}")
            }
            
            // Initialize objects to enable hierarchical references.
            for (entry : containerToArgs.entrySet) {
                val initializer = new StringJoiner(", ")
                for (variable : entry.value) {
                    initializer.add('''«variable.name»: __«entry.key.name»_«variable.name».get()''')
                    if (variable instanceof Input) {
                        pr(reactEpilogue, 
                        '''if («entry.key.name».«variable.name» !== undefined) {
                            __«entry.key.name»_«variable.name».set(«entry.key.name».«variable.name»)
                        }''')    
                    }
                                     
                }
                pr(reactPrologue, '''let «entry.key.name» = {«initializer»}''')
            }
            
            // Assemble reaction triggers          
            var reactionTriggers = new StringJoiner(", ") 
            for (trigger : reaction.triggers) {
                if (trigger instanceof VarRef) {
                    reactionTriggers.add("this." + trigger.generateVarRef)

                } else if (trigger.startup) {
                    reactionTriggers.add("this.startup")
                } else if (trigger.shutdown) {
                    reactionTriggers.add("this.shutdown")
                }
            }
            
            
            // Write the reaction itself
            pr(reactorConstructor, "this.addReaction(")//new class<T> extends Reaction<T> {")
            reactorConstructor.indent()
            pr(reactorConstructor, "new Triggers(" + reactionTriggers + "),")
            pr(reactorConstructor, "new Args(" + reactFunctArgs + "),")
            pr(reactorConstructor, "function (" + reactSignature + ") {")
            reactorConstructor.indent()
            pr(reactorConstructor, "// =============== START react prologue")
            pr(reactorConstructor, reactPrologue)
            pr(reactorConstructor, "// =============== END react prologue")
            pr(reactorConstructor, "try {")
            reactorConstructor.indent()
            pr(reactorConstructor, reaction.code.toText)
            reactorConstructor.unindent()
            pr(reactorConstructor, "} finally {")
            reactorConstructor.indent()
            pr(reactorConstructor, "// =============== START react epilogue")
            pr(reactorConstructor, reactEpilogue)
            pr(reactorConstructor, "// =============== END react epilogue")
            reactorConstructor.unindent()
            pr(reactorConstructor, "}")            
            reactorConstructor.unindent()  
            if (reaction.deadline === null) {
                pr(reactorConstructor, "}")
            } else {
                pr(reactorConstructor, "},")
                var deadlineArgs = ""
                if (reaction.deadline.delay.parameter !== null) {
                    deadlineArgs += "this." + reaction.deadline.delay.parameter.name + ".get()"; 
                } else {
                    deadlineArgs += reaction.deadline.delay.targetValue
                }
                pr(reactorConstructor, deadlineArgs + "," )
                pr(reactorConstructor, "function(" + reactSignature + ") {")
                reactorConstructor.indent()
                pr(reactorConstructor, "// =============== START deadline prologue")
                pr(reactorConstructor, reactPrologue)
                pr(reactorConstructor, "// =============== END deadline prologue")
                pr(reactorConstructor, "try {")
                reactorConstructor.indent()
                pr(reactorConstructor, toText(reaction.deadline.code))
                reactorConstructor.unindent()
                pr(reactorConstructor, "} finally {")
                reactorConstructor.indent()
                pr(reactorConstructor, "// =============== START deadline epilogue")
                pr(reactorConstructor, reactEpilogue)
                pr(reactorConstructor, "// =============== END deadline epilogue")
                reactorConstructor.unindent()
                pr(reactorConstructor, "}")  
                reactorConstructor.unindent()
                pr(reactorConstructor, "}")
            }
            reactorConstructor.unindent()
            pr(reactorConstructor, ");")
            
        }
        reactorConstructor.unindent()
        pr(reactorConstructor, "}")
        pr(reactorConstructor.toString())
        unindent()
        pr("}")
        pr("// =============== END reactor class " + reactor.name)
        pr("")
    }

    def generateArg(VarRef v) {
        if (v.container !== null) {
            '''__«v.container.name»_«v.variable.name»'''
        } else {
            '''__«v.variable.name»'''
        }
    }

    /** Generate the main app instance. This function is only used once
     *  because all other reactors are instantiated as properties of the
     *  main one.
     *  @param instance A reactor instance.
     */
    def void generateReactorInstance(Instantiation defn) {
        var fullName = defn.name

        // Iterate through parameters in the order they appear in the
        // main reactor class. If the parameter is typed such that it can
        // be a custom command line argument, use the parameter's command line
        // assignment variable ("__CL" + the parameter's name). That variable will
        // be undefined if the command line argument wasn't specified. Otherwise
        // use undefined in the constructor.
        var mainReactorParams = new StringJoiner(", ")
        for (parameter : defn.reactorClass.parameters) {
            
            if (customCLArgs.contains(parameter)) {
                mainReactorParams.add("__CL" + parameter.name)
            } else {
                mainReactorParams.add("undefined")
            }
        }

        pr('// ************* Instance ' + fullName + ' of class ' +
            defn.reactorClass.name)
        
        pr("let __app;")
        pr("if (!__noStart) {")
        indent()
        pr("__app = new "+ fullName + "(__timeout, __keepAlive, __fast, "
            + mainReactorParams + ");")
        unindent()
        pr("}")
    }
    
    /** Generate code to call the _start function on the main App
     *  instance to start the runtime
     *  @param instance A reactor instance.
     */
    def void generateRuntimeStart(Instantiation defn) {
        pr('// ************* Starting Runtime for ' + defn.name + ' of class ' +
            defn.reactorClass.name)
        pr("if (!__noStart && __app) {")
        indent()
        pr("__app._start();")
        unindent()
        pr("}")
    }


    // //////////////////////////////////////////
    // // Protected methods.

    /** Return a set of targets that are acceptable to this generator.
     *  Imported files that are Lingua Franca files must specify targets
     *  in this set or an error message will be reported and the import
     *  will be ignored. The returned set is a set of case-insensitive
     *  strings specifying target names.
     */
    override acceptableTargets() {
        acceptableTargetSet
    }
    

    /** Generate preamble code that appears in the code generated
     *  file before anything else.
     */
    override generatePreamble() {
        super.generatePreamble
        pr(preamble)
        pr("") 
        
        // Need to get the main reactor's parameters so they can be made
        // command line arguments
        var Reactor mainReactor
        
        for (reactor : resource.allContents.toIterable.filter(Reactor)) {
            if (reactor.isMain) {
                mainReactor = reactor
            }
        }
        
        // Build the argument spec for commandLineArgs and commandLineUsage
        var customArgs = new StringJoiner(",\n")
        
        // Extend the return type for commandLineArgs
        var clTypeExtension = new StringJoiner(", ")
        
        for (parameter : mainReactor.parameters) {
            var String customArgType = null;
            var String customTypeLabel = null;
            var paramType = parameter.targetType
            if (paramType == "string") {
                customCLArgs.add(parameter)
                //clTypeExtension.add(parameter.name + " : string")
                customArgType = "String";
            } else if (paramType == "number") {
                customCLArgs.add(parameter)
                //clTypeExtension.add(parameter.name + " : number")
                customArgType = "Number";
            } else if (paramType == "boolean") {
                customCLArgs.add(parameter)
                //clTypeExtension.add(parameter.name + " : boolean")
                customArgType = "booleanCLAType";
                customTypeLabel = '[true | false]'
            } else if (paramType == "TimeValue") {
                customCLArgs.add(parameter)
                //clTypeExtension.add(parameter.name + " : UnitBasedTimeValue | null")
                customArgType = "unitBasedTimeValueCLAType"
                customTypeLabel = "\'<duration> <units>\'"
            }
            // Otherwise don't add the parameter to customCLArgs
            
            
            if (customArgType !== null) {
                clTypeExtension.add(parameter.name + ": " + paramType)
                if (customTypeLabel !== null) {
                customArgs.add('''
                    { name: '«parameter.name»',
                        type: «customArgType»,
                        typeLabel: "{underline «customTypeLabel»}",
                        description: 'Custom argument. Refer to «sourceFile» for documentation.'
                    }
                    ''')
                } else {
                    customArgs.add('''
                        { name: '«parameter.name»',
                            type: «customArgType»,
                            description: 'Custom argument. Refer to «sourceFile» for documentation.'
                        }
                    ''')  
                }
            }  
        }
        
        var customArgsList = "[\n" + customArgs + "]"
        var clTypeExtensionDef = "{" + clTypeExtension + "}" 
        val setParameters = '''
            // ************* App Parameters
            let __timeout: TimeValue | undefined = «getTimeoutTimeValue»;
            let __keepAlive: boolean = «targetKeepalive»;
            let __fast: boolean = «targetFast»;
            
            let __noStart = false; // If set to true, don't start the app.
            
            // ************* Custom Command Line Arguments
            let __additionalCommandLineArgs : CommandLineOptionSpec = «customArgsList»;
            let __customCommandLineArgs = CommandLineOptionDefs.concat(__additionalCommandLineArgs);
            let __customCommandLineUsageDefs = CommandLineUsageDefs;
            type __customCLTypeExtension = «clTypeExtensionDef»;
            __customCommandLineUsageDefs[1].optionList = __customCommandLineArgs;
            const __clUsage = commandLineUsage(__customCommandLineUsageDefs);
                         
            // Set App parameters using values from the constructor or command line args.
            // Command line args have precedence over values from the constructor
            let __processedCLArgs: ProcessedCommandLineArgs & __customCLTypeExtension;
            try {
                __processedCLArgs =  commandLineArgs(__customCommandLineArgs) as ProcessedCommandLineArgs & __customCLTypeExtension;
            } catch (e){
                Log.global.error(__clUsage);
                throw new Error("Command line argument parsing failed with: " + e);
            }
            
            // Fast Parameter
            if (__processedCLArgs.fast !== undefined) {
                if (__processedCLArgs.fast !== null) {
                    __fast = __processedCLArgs.fast;
                } else {
                    Log.global.error(__clUsage);
                    throw new Error("'fast' command line argument is malformed.");
                }
            }
            
            // KeepAlive parameter
            if (__processedCLArgs.keepalive !== undefined) {
                if (__processedCLArgs.keepalive !== null) {
                    __keepAlive = __processedCLArgs.keepalive;
                } else {
                    Log.global.error(__clUsage);
                    throw new Error("'keepalive' command line argument is malformed.");
                }
            }
            
            // Timeout parameter
            if (__processedCLArgs.timeout !== undefined) {
                if (__processedCLArgs.timeout !== null) {
                    __timeout = __processedCLArgs.timeout;
                } else {
                    Log.global.error(__clUsage);
                    throw new Error("'timeout' command line argument is malformed.");
                }
            }
            
            // Logging parameter (not a constructor parameter, but a command line option)
            if (__processedCLArgs.logging !== undefined) {
                if (__processedCLArgs.logging !== null) {
                    Log.global.level = __processedCLArgs.logging;
                } else {
                    Log.global.error(__clUsage);
                    throw new Error("'logging' command line argument is malformed.");
                }
            } else {
                Log.global.level = Log.levels.«getLoggingLevel»; // Default from target property.
            }
            
            // Help parameter (not a constructor parameter, but a command line option)
            // NOTE: this arg has to be checked after logging, because the help mode should
            // suppress debug statements from it changes logging
            if (__processedCLArgs.help === true) {
                Log.global.error(__clUsage);
                __noStart = true;
                // Don't execute the app if the help flag is given.
            }
            
            // Now the logging property has been set to its final value,
            // log information about how command line arguments were set,
            // but only if not in help mode.
            
            // Runtime command line arguments 
            if (__processedCLArgs.fast !== undefined && __processedCLArgs.fast !== null
                && !__noStart) {
                Log.global.info("'fast' property overridden by command line argument.");
            }
            if (__processedCLArgs.keepalive !== undefined && __processedCLArgs.keepalive !== null
                && !__noStart) {
                Log.global.info("'keepalive' property overridden by command line argument.");
            }
            if (__processedCLArgs.timeout !== undefined && __processedCLArgs.timeout !== null
                && !__noStart) {
                Log.global.info("'timeout' property overridden by command line argument.");
            }
            if (__processedCLArgs.logging !== undefined && __processedCLArgs.logging !== null
                && !__noStart) {
                 Log.global.info("'logging' property overridden by command line argument.");
            }
            
            // Custom command line arguments
            «logCustomCLArgs()»
            
            // Assign custom command line arguments
            «assignCustomCLArgs()»
        '''
        
        pr(setParameters)
    }
    
    /**
     * Assign results of parsing custom command line arguments
     */
    private def assignCustomCLArgs() {
        var code = new StringJoiner("\n")
        for (parameter : customCLArgs) {
            code.add('''
                let __CL«parameter.name»: «parameter.targetType» | undefined = undefined;
                if (__processedCLArgs.«parameter.name» !== undefined) {
                    if (__processedCLArgs.«parameter.name» !== null) {
                        __CL«parameter.name» = __processedCLArgs.«parameter.name»;
                    } else {
                        Log.global.error(__clUsage);
                        throw new Error("Custom '«parameter.name»' command line argument is malformed.");
                    }
                }
            ''')
        }
        code.toString()
    }
    
    /**
     * Generate code for extracting custom command line arguments
     * from the object returned from commandLineArgs
     */
    private def logCustomCLArgs() {
        var code = new StringJoiner("\n")
        for (parameter : customCLArgs) {
            // We can't allow the programmer's parameter names
            // to cause the generation of variables with a "__" prefix
            // because they could collide with other variables.
            // So prefix variables created here with __CL
            code.add('''
                if (__processedCLArgs.«parameter.name» !== undefined && __processedCLArgs.«parameter.name» !== null
                    && !__noStart) {
                    Log.global.info("'«parameter.name»' property overridden by command line argument.");
                }
            ''')
        }
        code.toString()
    }


    /** Given a representation of time that may possibly include units,
     *  return a string that TypeScript can recognize as a value.
     *  @param time Literal that represents a time value.
     *  @param unit Enum that denotes units
     *  @return A string, as "[ timeLiteral, TimeUnit.unit]" .
     */
    override timeInTargetLanguage(TimeValue value) {
        if (value.unit != TimeUnit.NONE) {
            "new UnitBasedTimeValue(" + value.time + ", TimeUnit." + value.unit + ")"
        } else {
            // The default time unit for TypeScript is msec.
            "new UnitBasedTimeValue(" + value.time + ", TimeUnit.msec)" // FIXME: times should always have units associated with them.
        }
    }

    // //////////////////////////////////////////
    // // Private methods.
    
    /** Look for a "logging" target property and return
     *  the appropriate logging level. This level is a
     *  subset of Log.level enum from the ulog module
     *  https://www.npmjs.com/package/ulog. Logged messages
     *  will display if the level of the message <= the logging level.
     *  For now, these log levels are:
     *  Error < Warn < Info < Log < Debug.
     *  The case of the level when expressed as a target property
     *  doesn't matter, but the return value from this function is
     *  in all caps.
     *  @return The logging target property's value in all caps.
     */
    private def getLoggingLevel() {
        if (targetLoggingLevel === null) {
            LoggingLevels.ERROR.toString
        } else {
            targetLoggingLevel
        }
    }
    
    /** Copy the designated file from reactor-ts core into the target
     *  directory.
     *  @param targetPath The path to where the copied file will be placed.
     *  @param filename The path to the file from reactor-ts core to copy.
     */
    private def copyReactorTSCoreFile(String targetPath, String filename) {
        copyFileFromClassPath(
            reactorTSCorePath + filename,
            targetPath + File.separator + filename
        )
    }
    
    /** If the given filename doesn't already exist in the targetPath
     *  create it by copying over the default from /lib/TS/. Do nothing
     *  if the file already exists because we don't want to overwrite custom
     *  user-specified configurations. 
     *  @param targetPath The path to the where the file will be copied.
     *  @param filename The name of the file for which to create a default in
     *    the root of the project directory
     *  @return true if the file was created, false otherwise.
     */
    private def createDefaultConfigFile(String targetPath, String filename) {
        var File defaultFile = new File(targetPath + File.separator + filename)
        val libFile = configPath + File.separator + filename
        if(!defaultFile.exists()){
            println(filename + " does not already exist for this project."
                + " Copying over default from " + libFile)
            copyFileFromClassPath(libFile, targetPath + File.separator + filename)
        } else {
            println("This project already has " + targetPath + File.separator + filename)
        }
    }


    /** Return a TS type for the type of the specified state.
     *  If there are code delimiters around it, those are removed.
     *  If the type is "time", then it is converted to "TimeValue".
     *  If state is a parameter, get the parameter's type.
     *  If the state doesn't have a type, type it as 'unknown'
     *  @param state The state.
     *  @return The TS type.
     */
    private def getStateType(StateVar state) {
        state.getTargetType
    }
    
    /**
     * Return a TS type for the specified action.
     * If the type has not been specified, return
     * "Present" which is the base type for Actions.
     * @param action The action
     * @return The TS type.
     */
    private def getActionType(Action action) {
        if (action.type !== null) {
            return action.type.targetType
        } else {
            return "Present"    
        }
    }
    
     /**
     * Return a TS type for the specified port.
     * If the type has not been specified, return
     * "Present" which is the base type for ports.
     * @param port The port
     * @return The TS type.
     */
    private def getPortType(Port port) {
        if (port.type !== null) {
            return port.type.targetType
        } else {
            return "Present"    
        }
    }


    def String getTargetInitializer(StateVar state) {
        '''«FOR init : state.initializerList SEPARATOR ", "»«init»«ENDFOR»'''
    }

    def private String getTargetInitializerHelper(Parameter param,
        List<String> list) {
        if (list.size == 0) {
            param.reportError("Parameters must have a default value!")
        } else if (list.size == 1) {
            return list.get(0)
        } else {
            '''[«FOR init : list SEPARATOR ", "»«init»«ENDFOR»]'''
        }
    }

    def String getTargetInitializer(Parameter param) {
        return getTargetInitializerHelper(param, param.initializerList)
    }

    def String getTargetInitializer(Parameter param, Instantiation i) {
        return '''«getTargetInitializerHelper(param, param.getInitializerList(i))»'''
    }

	def initializeParameter(Parameter p) 
		'''«p.name»:«p.targetType» = «p.getTargetInitializer()»'''
    
    override getTargetType(StateVar s) {
        val type = super.getTargetType(s)
        if (!s.isInitialized) {
        	type + " | undefined"
        } else {
        	type
        }
    }
    
    private def getTimeoutTimeValue() {
        if (targetTimeout >= 0) {
            return timeInTargetLanguage(new TimeValue(targetTimeout, targetTimeoutUnit))
        } else {
            return "undefined"
        }
    }

    static val reactorLibPath = "." + File.separator + "reactor"
    static val timeLibPath =  "." + File.separator + "time"
    static val utilLibPath =  "." + File.separator + "util"
    static val cliLibPath =  "." + File.separator + "cli"
    static val preamble = 
'''import commandLineArgs from 'command-line-args'
import commandLineUsage from 'command-line-usage'
import {Args, Present, Parameter, State, Variable, Priority, Mutation, Read, Triggers, ReadWrite, Write, Named, Reaction, Action, Startup, Schedule, Timer, Reactor, Port, OutPort, InPort, App} from '«reactorLibPath»'
import {TimeUnit, TimeValue, UnitBasedTimeValue, Tag, Origin} from '«timeLibPath»'
import {Log} from '«utilLibPath»'
import {ProcessedCommandLineArgs, CommandLineOptionDefs, CommandLineUsageDefs, CommandLineOptionSpec, unitBasedTimeValueCLAType, booleanCLAType} from '«cliLibPath»'

'''
        
    override String getTargetTimeType() {
        "TimeValue"
    }
    
    override String getTargetUndefinedType() {
        "unknown"
    }
    
    override String getTargetFixedSizeListType(String baseType, Integer size) {
        '''Array(«size»)<«baseType»>'''
    }
    
    override String getTargetVariableSizeListType(String baseType) {
        '''Array<«baseType»>'''
    }
    
    override supportsGenerics() {
        true
    }
    
    override String generateDelayGeneric()
        '''T extends Present'''

}
