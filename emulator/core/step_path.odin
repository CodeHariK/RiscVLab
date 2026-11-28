package rv

import "base:runtime"

// The step's path through the emulator: which of its functions the step
// went through, in call order, so the debugger can show where in this
// code an instruction is handled:
//
//   machine_step -> cpu_step -> execute -> exec_system -> exec_mret
//
// Each function on the way records itself by calling step_path_push at
// its top. Only the stages a reader would open are recorded (the ones in
// Step_Stage), not every helper. Like the undo record, this exists only in
// a build that records steps: every push is inside `when
// DEBUG_RECORD_STEPS { }`.
//
// Recorded at run time rather than kept as a table "instruction ->
// functions", so it can't go stale when a function is renamed or split:
// a unit test build (ODIN_TEST) checks that every push is made from the
// function its stage names, in the file it names.

// The functions a step can go through, in roughly the order they run.
// Each name is its function's name, capitalised (STEP_STAGES has both).
Step_Stage :: enum u8 {
	Machine_Step,
	Interrupt_To_Take,
	Cpu_Step,
	Execute,
	Exec_Lui,
	Exec_Auipc,
	Exec_Jal,
	Exec_Jalr,
	Exec_Branch,
	Exec_Load,
	Exec_Store,
	Exec_Op_Imm,
	Exec_Op,
	Exec_Op_Imm_32,
	Exec_Op_32,
	Exec_Muldiv,
	Exec_Muldiv_32,
	Exec_Amo,
	Exec_Lr,
	Exec_Sc,
	Exec_Read_Modify_Write,
	Exec_System,
	Exec_Zicsr,
	Exec_Mret,
	Exec_Sret,
	Trap_Target,
	Trap_Enter,
	Trap_Enter_Machine,
	Trap_Enter_Supervisor,
}

// A stage's function, the file it is in (relative to the emulator
// folder), and the stage that calls it, for the debugger to draw the step
// as a tree of calls: a trap isn't entered from inside the instruction,
// machine_step does it after cpu_step returns.
Step_Stage_Info :: struct {
	procedure: string,
	file:      string,
	parent:    Step_Stage, // the caller; machine_step, the root, names itself
}

STEP_STAGES := [Step_Stage]Step_Stage_Info {
	.Machine_Step           = {"machine_step", "core/machine.odin", .Machine_Step},
	.Interrupt_To_Take      = {"interrupt_to_take", "core/interrupts.odin", .Machine_Step},
	.Cpu_Step               = {"cpu_step", "core/cpu.odin", .Machine_Step},
	.Execute                = {"execute", "core/execute.odin", .Cpu_Step},
	.Exec_Lui               = {"exec_lui", "core/rv64i_upper.odin", .Execute},
	.Exec_Auipc             = {"exec_auipc", "core/rv64i_upper.odin", .Execute},
	.Exec_Jal               = {"exec_jal", "core/rv64i_control.odin", .Execute},
	.Exec_Jalr              = {"exec_jalr", "core/rv64i_control.odin", .Execute},
	.Exec_Branch            = {"exec_branch", "core/rv64i_control.odin", .Execute},
	.Exec_Load              = {"exec_load", "core/rv64i_load_store.odin", .Execute},
	.Exec_Store             = {"exec_store", "core/rv64i_load_store.odin", .Execute},
	.Exec_Op_Imm            = {"exec_op_imm", "core/rv64i_alu.odin", .Execute},
	.Exec_Op                = {"exec_op", "core/rv64i_alu.odin", .Execute},
	.Exec_Op_Imm_32         = {"exec_op_imm_32", "core/rv64i_alu_word.odin", .Execute},
	.Exec_Op_32             = {"exec_op_32", "core/rv64i_alu_word.odin", .Execute},
	.Exec_Muldiv            = {"exec_muldiv", "core/rv64m.odin", .Exec_Op},
	.Exec_Muldiv_32         = {"exec_muldiv_32", "core/rv64m.odin", .Exec_Op_32},
	.Exec_Amo               = {"exec_amo", "core/rv64a.odin", .Execute},
	.Exec_Lr                = {"exec_lr", "core/rv64a.odin", .Exec_Amo},
	.Exec_Sc                = {"exec_sc", "core/rv64a.odin", .Exec_Amo},
	.Exec_Read_Modify_Write = {"exec_read_modify_write", "core/rv64a.odin", .Exec_Amo},
	.Exec_System            = {"exec_system", "core/rv64i_system.odin", .Execute},
	.Exec_Zicsr             = {"exec_zicsr", "core/zicsr.odin", .Exec_System},
	.Exec_Mret              = {"exec_mret", "core/trap_return.odin", .Exec_System},
	.Exec_Sret              = {"exec_sret", "core/trap_return.odin", .Exec_System},
	.Trap_Target            = {"trap_target", "core/trap_entry.odin", .Machine_Step},
	.Trap_Enter             = {"trap_enter", "core/trap_entry.odin", .Machine_Step},
	.Trap_Enter_Machine     = {"trap_enter_machine", "core/trap_entry.odin", .Trap_Enter},
	.Trap_Enter_Supervisor  = {"trap_enter_supervisor", "core/trap_entry.odin", .Trap_Enter},
}

// The longest path a step takes is 8 stages (an illegal CSR access:
// machine_step, cpu_step, execute, exec_system, exec_zicsr, trap_target,
// trap_enter, trap_enter_machine); 12 leaves room.
STEP_PATH_MAX :: 12

// One step's path. Fixed size and small (13 bytes), so the debugger can
// keep one per step.
Step_Path :: struct {
	stages: [STEP_PATH_MAX]Step_Stage,
	count:  u8,
}

// The stages recorded, in call order.
step_path_stages :: proc(path: ^Step_Path) -> []Step_Stage {
	return path.stages[:path.count]
}

// Records that the step reached `stage`. Called at the top of the
// function `stage` names, inside `when DEBUG_RECORD_STEPS { }` like the
// rest of the step recording, so a build that doesn't record has no trace
// of it. machine_step clears the path first.
@(private)
step_path_push :: #force_inline proc(cpu: ^Cpu, stage: Step_Stage, location := #caller_location) {
	when ODIN_TEST {
		step_path_check(&cpu.debug_path, stage, location)
	}
	path := &cpu.debug_path
	if int(path.count) < STEP_PATH_MAX {
		path.stages[path.count] = stage
		path.count += 1
	}
}

// Unit test builds only: the push for `stage` must come from the function
// and file STEP_STAGES gives for it, after its caller's, so a renamed,
// moved or newly called function fails the tests instead of showing a
// stale name or a wrong tree in the debugger.
@(private = "file")
step_path_check :: proc(path: ^Step_Path, stage: Step_Stage, location: runtime.Source_Code_Location) {
	info := STEP_STAGES[stage]
	// The caller STEP_STAGES names must already be on the path (machine_step
	// starts it): a function called from somewhere new fails here.
	has_parent := stage == .Machine_Step
	for earlier in step_path_stages(path) {
		has_parent ||= earlier == info.parent
	}
	assert(has_parent, "step_path_push: STEP_STAGES names the wrong caller for this stage")
	assert(location.procedure == info.procedure, "step_path_push: the stage doesn't name the function it is pushed from")
	file := location.file_path
	assert(len(file) >= len(info.file) && file[len(file) - len(info.file):] == info.file, "step_path_push: STEP_STAGES has the wrong file for this stage")
}
