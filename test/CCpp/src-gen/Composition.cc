// Code generated by the Lingua Franca compiler from file:
// /home/soroosh/lingua-franca/test/CCpp/Composition.lf
#include "ctarget.h"
#define NUMBER_OF_FEDERATES 1
#include "core/reactor.c"
// =============== START reactor class Source
typedef struct {
    int value;
    bool is_present;
    int num_destinations;
} source_y_t;
typedef struct {
    #line 7 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    interval_t period;
    #line 10 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    int count;
    #line 8 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    source_y_t __y;
    #line 11 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    reaction_t ___reaction_0;
    bool* __reaction_0_outputs_are_present[1];
    int __reaction_0_num_outputs;
    trigger_t** __reaction_0_triggers[1];
    int __reaction_0_triggered_sizes[1];
    #line 9 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    trigger_t ___t;
    #line 9 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    reaction_t* ___t_reactions[1];
} source_self_t;
void sourcereaction_function_0(void* instance_args) {
    source_self_t* self = (source_self_t*)instance_args;
    source_y_t* y = &self->__y;
    #line 12 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->count++;
    std::cout << "Source sending" << self->count << "." << std::endl;
    y->set(count);
        
}
source_self_t* new_Source() {
    source_self_t* self = (source_self_t*)calloc(1, sizeof(source_self_t));
    self->__reaction_0_outputs_are_present[0] = &self->__y.is_present;
    self->__reaction_0_num_outputs = 1;
    #line 11 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.function = sourcereaction_function_0;
    #line 11 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.self = self;
    #line 11 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.num_outputs = 1;
    #line 11 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.output_produced = self->__reaction_0_outputs_are_present;
    #line 11 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.triggered_sizes = self->__reaction_0_triggered_sizes;
    #line 11 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.triggers = self->__reaction_0_triggers;
    #line 11 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.deadline_violation_handler = NULL;
    #line 9 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___t.scheduled = NEVER;
    #line 9 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___t_reactions[0] = &self->___reaction_0;
    self->___t.reactions = &self->___t_reactions[0];
    self->___t.number_of_reactions = 1;
    self->___t.is_timer = true;
    return self;
}
// =============== END reactor class Source

// =============== START reactor class Test
typedef struct {
    int value;
    bool is_present;
    int num_destinations;
} test_x_t;
typedef struct {
    trigger_t* trigger;
    bool is_present;
    bool has_value;
    token_t* token;
} test_shutdown_t;
typedef struct {
    #line 20 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    int count;
    test_shutdown_t __shutdown;
    #line 19 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    test_x_t* __x;
    #line 21 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    reaction_t ___reaction_0;
    bool* __reaction_0_outputs_are_present[0];
    int __reaction_0_num_outputs;
    trigger_t** __reaction_0_triggers[0];
    int __reaction_0_triggered_sizes[0];
    #line 29 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    reaction_t ___reaction_1;
    bool* __reaction_1_outputs_are_present[0];
    int __reaction_1_num_outputs;
    trigger_t** __reaction_1_triggers[0];
    int __reaction_1_triggered_sizes[0];
    trigger_t ___shutdown;
    reaction_t* ___shutdown_reactions[1];
    #line 19 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    trigger_t ___x;
    #line 19 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    reaction_t* ___x_reactions[1];
} test_self_t;
void testreaction_function_0(void* instance_args) {
    test_self_t* self = (test_self_t*)instance_args;
    test_x_t* x = self->__x;
    int x_width = -2;
    #line 22 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->count++; // local variables declared here that are not state variables should be strongly discouraged
    std::cout << "Received " << x << std::endl; // Or x->get()
    if (x != self->count) { // Or x->get()
        std::cerr << "FAILURE: Expected " <<  count << endl; // could be this->count as well
        exit(1); 
    }
        
}
void testreaction_function_1(void* instance_args) {
    test_self_t* self = (test_self_t*)instance_args;
    // Expose the action struct as a local variable whose name matches the action name.
    test_shutdown_t* shutdown = &self->__shutdown;
    // Set the fields of the action struct to match the current trigger.
    shutdown->is_present = self->___shutdown.is_present;
    shutdown->has_value = ((self->___shutdown.token) != NULL && (self->___shutdown.token)->value != NULL);
    shutdown->token = (self->___shutdown.token);
    #line 30 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    if (count == 0) {
        std::cerr << "FAILURE: No data received." << std::endl;
    }
        
}
test_self_t* new_Test() {
    test_self_t* self = (test_self_t*)calloc(1, sizeof(test_self_t));
    self->__shutdown.trigger = &self->___shutdown;
    self->__reaction_0_num_outputs = 0;
    #line 21 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.function = testreaction_function_0;
    #line 21 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.self = self;
    #line 21 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.num_outputs = 0;
    #line 21 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.output_produced = self->__reaction_0_outputs_are_present;
    #line 21 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.triggered_sizes = self->__reaction_0_triggered_sizes;
    #line 21 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.triggers = self->__reaction_0_triggers;
    #line 21 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_0.deadline_violation_handler = NULL;
    self->__reaction_1_num_outputs = 0;
    #line 29 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_1.function = testreaction_function_1;
    #line 29 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_1.self = self;
    #line 29 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_1.num_outputs = 0;
    #line 29 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_1.output_produced = self->__reaction_1_outputs_are_present;
    #line 29 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_1.triggered_sizes = self->__reaction_1_triggered_sizes;
    #line 29 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_1.triggers = self->__reaction_1_triggers;
    #line 29 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___reaction_1.deadline_violation_handler = NULL;
    self->___shutdown.scheduled = NEVER;
    self->___shutdown_reactions[0] = &self->___reaction_1;
    self->___shutdown.reactions = &self->___shutdown_reactions[0];
    self->___shutdown.number_of_reactions = 1;
    self->___shutdown.is_physical = false;
    self->___shutdown.drop = false;
    self->___shutdown.element_size = 0;
    #line 19 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___x.scheduled = NEVER;
    #line 19 "file:/home/soroosh/lingua-franca/test/CCpp/Composition.lf"
    self->___x_reactions[0] = &self->___reaction_0;
    self->___x.reactions = &self->___x_reactions[0];
    self->___x.number_of_reactions = 1;
    self->___x.element_size = sizeof(int);
    return self;
}
// =============== END reactor class Test

// =============== START reactor class Composition
typedef struct {
    bool hasContents;
} composition_self_t;
composition_self_t* new_Composition() {
    composition_self_t* self = (composition_self_t*)calloc(1, sizeof(composition_self_t));
    return self;
}
// =============== END reactor class Composition

char* __default_argv[] = {"X", "-f", "true", "-o", "10", "sec"};
void __set_default_command_line_options() {
    default_argc = 6;
    default_argv = __default_argv;
}
// Array of pointers to timer triggers to start the timers in __start_timers().
trigger_t* __timer_triggers[1];
int __timer_triggers_size = 1;
// Array of pointers to shutdown triggers.
trigger_t* __shutdown_triggers[1];
int __shutdown_triggers_size = 1;
trigger_t* __action_for_port(int port_id) {
    return NULL;
}
void __initialize_trigger_objects() {
    __tokens_with_ref_count_size = 1;
    __tokens_with_ref_count = (token_present_t*)malloc(1 * sizeof(token_present_t));
    // Create the array that will contain pointers to is_present fields to reset on each step.
    __is_present_fields_size = 2;
    __is_present_fields = (bool**)malloc(2 * sizeof(bool*));
    // ************* Instance Composition of class Composition
    composition_self_t* composition_self = new_Composition();
    //***** Start initializing Composition
    // ************* Instance Composition.s of class Source
    source_self_t* composition_s_self = new_Source();
    //***** Start initializing Composition.s
    composition_s_self->period = SEC(2); 
    static int composition_s_initial_count = 0;
    composition_s_self->count = composition_s_initial_count;
    // Reaction 0 of Composition.s triggers 1 downstream reactions through port Composition.s.y.
    composition_s_self->___reaction_0.triggered_sizes[0] = 1;
    // For reaction 0 of Composition.s, allocate an
    // array of trigger pointers for downstream reactions through port Composition.s.y
    trigger_t** composition_s_0_0 = (trigger_t**)malloc(1 * sizeof(trigger_t*));
    composition_s_self->___reaction_0.triggers[0] = composition_s_0_0;
    composition_s_self->___t.offset = SEC(1);
    composition_s_self->___t.period = SEC(2);
    __timer_triggers[0] = &composition_s_self->___t;
    composition_s_self->__y.num_destinations = 1;
    //***** End initializing Composition.s
    // ************* Instance Composition.d of class Test
    test_self_t* composition_d_self = new_Test();
    //***** Start initializing Composition.d
    static int composition_d_initial_count = 0;
    composition_d_self->count = composition_d_initial_count;
    composition_d_self->___shutdown.offset = 0;
    composition_d_self->___shutdown.period = 0;
    __shutdown_triggers[0] = &composition_d_self->___shutdown;
    composition_d_self->___shutdown.token = __create_token(0);
    composition_d_self->___shutdown.is_present = false;
    __tokens_with_ref_count[0].token
            = &composition_d_self->___shutdown.token;
    __tokens_with_ref_count[0].is_present
            = &composition_d_self->___shutdown.is_present;
    __tokens_with_ref_count[0].reset_is_present = true;
    //***** End initializing Composition.d
    //***** End initializing Composition
    // Populate arrays of trigger pointers.
    // Point to destination port Composition.d.x's trigger struct.
    composition_s_0_0[0] = &composition_d_self->___x;
    // doDeferredInitialize
    composition_d_self->__x = NULL;
    // Connect inputs and outputs for reactor Composition.
    // Connect Composition.s.y to input port Composition.d.x
    composition_d_self->__x = (test_x_t*)&composition_s_self->__y;
    // Connect inputs and outputs for reactor Composition.s.
    // END Connect inputs and outputs for reactor Composition.s.
    // Connect inputs and outputs for reactor Composition.d.
    // END Connect inputs and outputs for reactor Composition.d.
    // END Connect inputs and outputs for reactor Composition.
    // Add action Composition.d.shutdown to array of is_present fields.
    __is_present_fields[0] 
            = &composition_d_self->__shutdown.is_present;
    // Add port Composition.s.y to array of is_present fields.
    __is_present_fields[1] = &composition_s_self->__y.is_present;
    composition_s_self->___reaction_0.chain_id = 1;
    // index is the OR of level 0 and 
    // deadline 140737488355327 shifted left 16 bits.
    composition_s_self->___reaction_0.index = 0x7fffffffffff0000LL;
    composition_d_self->___reaction_0.chain_id = 1;
    // index is the OR of level 1 and 
    // deadline 140737488355327 shifted left 16 bits.
    composition_d_self->___reaction_0.index = 0x7fffffffffff0001LL;
    composition_d_self->___reaction_1.chain_id = 1;
    // index is the OR of level 2 and 
    // deadline 140737488355327 shifted left 16 bits.
    composition_d_self->___reaction_1.index = 0x7fffffffffff0002LL;
}
void __start_timers() {
    
    for (int i = 0; i < __timer_triggers_size; i++) {
        __schedule(__timer_triggers[i], 0LL, NULL);
    }
}
void logical_time_complete(instant_t time) {
}
instant_t next_event_time(instant_t time) {
    return time;
}
bool __wrapup() {
    __start_time_step();  // To free memory allocated for actions.
    for (int i = 0; i < __shutdown_triggers_size; i++) {
        __schedule(__shutdown_triggers[i], 0LL, NULL);
    }
    // Return true if there are shutdown actions.
    return (__shutdown_triggers_size > 0);
}
void __termination() {}
