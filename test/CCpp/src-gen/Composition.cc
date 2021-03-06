// Code generated by the Lingua Franca compiler from file:
// /home/soroosh/lingua-franca/test/CCpp/Composition.lf

#define NUMBER_OF_FEDERATES 1
#include "cpptarget.h"

// =============== START reactor class Source
class source_self_t {
public:
	interval_t period;
	int count;
	Port<int> __y;
	//bool __y_is_present;
    
    int __y_num_destinations;
	reaction_t ___reaction_0;
	bool* __reaction_0_outputs_are_present[1];
	int __reaction_0_num_outputs;
	trigger_t** __reaction_0_triggers[1];
	int __reaction_0_triggered_sizes[1];
	trigger_t ___t;
	reaction_t* ___t_reactions[1];
//public:
    static void reaction_function_0(void* instance_args) {
        source_self_t* self = (source_self_t*)instance_args;
        // auto y = this->__y;
        // bool y_is_present = this->__y.is_present();
        self->count++;
        std::cout << "Source sending " << self->count << "." << std::endl;
        self->__y.set(self->count);

    }

	source_self_t() {
		this->__reaction_0_outputs_are_present[0] = &this->__y._is_present;
		this->__reaction_0_num_outputs = 1;
		this->___reaction_0.function = reaction_function_0;
		this->___reaction_0.self = this; // Doesn't seem to break anything in this example
		this->___reaction_0.num_outputs = 1;
		this->___reaction_0.output_produced = this->__reaction_0_outputs_are_present;
		this->___reaction_0.triggered_sizes = this->__reaction_0_triggered_sizes;
		this->___reaction_0.triggers = this->__reaction_0_triggers;
		this->___reaction_0.deadline_violation_handler = NULL;
		this->___t.scheduled = NEVER;
		this->___t_reactions[0] = &this->___reaction_0;
		this->___t.reactions = &this->___t_reactions[0];
		this->___t.number_of_reactions = 1;
		this->___t.is_timer = true;
	}
};
// =============== END reactor class Source

// =============== START reactor class Test
class test_self_t {
public:
	int count;
	Port<int>* __x;
	//bool* __x_is_present;
	reaction_t ___reaction_0;
	bool* __reaction_0_outputs_are_present[0];
	int __reaction_0_num_outputs;
	trigger_t** __reaction_0_triggers[0];
	int __reaction_0_triggered_sizes[0];
	reaction_t ___reaction_1;
	bool* __reaction_1_outputs_are_present[0];
	int __reaction_1_num_outputs;
	trigger_t** __reaction_1_triggers[0];
	int __reaction_1_triggered_sizes[0];
	trigger_t ___shutdown;
	reaction_t* ___shutdown_reactions[1];
	trigger_t ___x;
	reaction_t* ___x_reactions[1];
//public:
    static void reaction_function_0(void* instance_args) {
        test_self_t* self = (test_self_t*)instance_args;
        bool x_is_present = self->__x->is_present();
        int x;
        if (x_is_present) {
            x = self->__x->get();
        }
        self->count++; // local variables declared here that are not state variables should be strongly discouraged
        std::cout << "Received " << x << std::endl; // Or x->get()
        if (x != self->count) { // Or x->get()
            std::cerr << "FAILURE: Expected " <<  self->count << std::endl; // could be this->count as well
            exit(1); 
        }

    }
    static void reaction_function_1(void* instance_args) {
        test_self_t* self = (test_self_t*)instance_args;
        bool shutdown_is_present = self->___shutdown.is_present;
        bool shutdown_has_value = ((self->___shutdown.token) != NULL && (self->___shutdown.token)->value != NULL);
        token_t* shutdown_token = (self->___shutdown.token);
        if (self->count == 0) {
            std::cerr << "FAILURE: No data received." << std::endl;
        }

    }
	test_self_t() {
		this->__reaction_0_num_outputs = 0;
		this->___reaction_0.function = reaction_function_0;
		this->___reaction_0.self = this; // Doesn't seem to break anything in this example.
		this->___reaction_0.num_outputs = 0;
		this->___reaction_0.output_produced = this->__reaction_0_outputs_are_present;
		this->___reaction_0.triggered_sizes = this->__reaction_0_triggered_sizes;
		this->___reaction_0.triggers = this->__reaction_0_triggers;
		this->___reaction_0.deadline_violation_handler = NULL;
		this->__reaction_1_num_outputs = 0;
		this->___reaction_1.function = reaction_function_1;
		this->___reaction_1.self = this; // Doesn't seem to break anything in this example.
		this->___reaction_1.num_outputs = 0;
		this->___reaction_1.output_produced = this->__reaction_1_outputs_are_present;
		this->___reaction_1.triggered_sizes = this->__reaction_1_triggered_sizes;
		this->___reaction_1.triggers = this->__reaction_1_triggers;
		this->___reaction_1.deadline_violation_handler = NULL;
		this->___shutdown.scheduled = NEVER;
		this->___shutdown_reactions[0] = &this->___reaction_1;
		this->___shutdown.reactions = &this->___shutdown_reactions[0];
		this->___shutdown.number_of_reactions = 1;
		this->___shutdown.is_physical = false;
		this->___shutdown.drop = false;
		this->___shutdown.element_size = 0;
		this->___x.scheduled = NEVER;
		this->___x_reactions[0] = &this->___reaction_0;
		this->___x.reactions = &this->___x_reactions[0];
		this->___x.number_of_reactions = 1;
		this->___x.element_size = sizeof(int);
	}
};
// =============== END reactor class Test


// =============== START reactor class Composition
class composition_self_t {
public:
	bool hasContents;
//public:
	composition_self_t() {
	}
};
// =============== END reactor class Composition

char* __default_argv[] = {"X", "-f", "true", "-o", "10", "sec"};
void __set_default_command_line_options() {
	default_argc = 6;
	default_argv = __default_argv;
}
// Array of pointers to timer triggers to start the timers in __start_timers().
trigger_t* __timer_triggers[1];
int __timer_triggers_size = 1;
trigger_t* __action_for_port(int port_id) {
	return NULL;
}
void __initialize_trigger_objects() {
	__tokens_with_ref_count_size = 1;
	__tokens_with_ref_count = (token_present_t*)malloc(1 * sizeof(token_present_t));
	// Create the array that will contain pointers to _is_present fields to reset on each step.
	__is_present_fields_size = 1;
	__is_present_fields = (bool**)malloc(1 * sizeof(bool*));
	// ************* Instance Composition of class Composition
	composition_self_t* composition_self = new composition_self_t();
	//***** Start initializing Composition
	// ************* Instance Composition.s of class Source
	source_self_t* composition_s_self = new source_self_t();
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
	composition_s_self->__y_num_destinations = 1;
	//***** End initializing Composition.s
	// ************* Instance Composition.d of class Test
	test_self_t* composition_d_self = new test_self_t();
	//***** Start initializing Composition.d
	static int composition_d_initial_count = 0;
	composition_d_self->count = composition_d_initial_count;
	composition_d_self->___shutdown.offset = 0;
	composition_d_self->___shutdown.period = 0;
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
	// composition_d_self->__x->_is_present = &absent; // I don't understand why this is set immidiately before re-initialization
	// Connect inputs and outputs for reactor Composition.
	// Connect Composition.s.y to input port Composition.d.x
	composition_d_self->__x = composition_s_self->__y.get_pointer();
	composition_d_self->__x->_is_present = composition_s_self->__y._is_present;
	// Connect inputs and outputs for reactor Composition.s.
	// END Connect inputs and outputs for reactor Composition.s.
	// Connect inputs and outputs for reactor Composition.d.
	// END Connect inputs and outputs for reactor Composition.d.
	// END Connect inputs and outputs for reactor Composition.
	// Add port Composition.s.y to array of _is_present fields.
	__is_present_fields[0] = &composition_s_self->__y._is_present;
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
	__start_time_step();   // To free memory allocated for actions.
	return false;
}
void __termination() {}
