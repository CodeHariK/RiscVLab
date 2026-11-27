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

// A stage's function and the file it is in (relative to the emulator
// folder), for the debugger to show.
Step_Stage_Info :: struct {
	procedure: string,
	file:      string,
}

STEP_STAGES := [Step_Stage]Step_Stage_Info {
	.Machine_Step           = {"machine_step", "core/machine.odin"},
	.Interrupt_To_Take      = {"interrupt_to_take", "core/interrupts.odin"},
	.Cpu_Step               = {"cpu_step", "core/cpu.odin"},
	.Execute                = {"execute", "core/execute.odin"},
	.Exec_Lui               = {"exec_lui", "core/rv64i_upper.odin"},
	.Exec_Auipc             = {"exec_auipc", "core/rv64i_upper.odin"},
	.Exec_Jal               = {"exec_jal", "core/rv64i_control.odin"},
	.Exec_Jalr              = {"exec_jalr", "core/rv64i_control.odin"},
	.Exec_Branch            = {"exec_branch", "core/rv64i_control.odin"},
	.Exec_Load              = {"exec_load", "core/rv64i_load_store.odin"},
	.Exec_Store             = {"exec_store", "core/rv64i_load_store.odin"},
	.Exec_Op_Imm            = {"exec_op_imm", "core/rv64i_alu.odin"},
	.Exec_Op                = {"exec_op", "core/rv64i_alu.odin"},
	.Exec_Op_Imm_32         = {"exec_op_imm_32", "core/rv64i_alu_word.odin"},
	.Exec_Op_32             = {"exec_op_32", "core/rv64i_alu_word.odin"},
	.Exec_Muldiv            = {"exec_muldiv", "core/rv64m.odin"},
	.Exec_Muldiv_32         = {"exec_muldiv_32", "core/rv64m.odin"},
	.Exec_Amo               = {"exec_amo", "core/rv64a.odin"},
	.Exec_Lr                = {"exec_lr", "core/rv64a.odin"},
	.Exec_Sc                = {"exec_sc", "core/rv64a.odin"},
	.Exec_Read_Modify_Write = {"exec_read_modify_write", "core/rv64a.odin"},
	.Exec_System            = {"exec_system", "core/rv64i_system.odin"},
	.Exec_Zicsr             = {"exec_zicsr", "core/zicsr.odin"},
	.Exec_Mret              = {"exec_mret", "core/privilege.odin"},
	.Exec_Sret              = {"exec_sret", "core/privilege.odin"},
	.Trap_Target            = {"trap_target", "core/privilege.odin"},
	.Trap_Enter             = {"trap_enter", "core/privilege.odin"},
	.Trap_Enter_Machine     = {"trap_enter_machine", "core/privilege.odin"},
	.Trap_Enter_Supervisor  = {"trap_enter_supervisor", "core/privilege.odin"},
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
		step_path_check(stage, location)
	}
	path := &cpu.debug_path
	if int(path.count) < STEP_PATH_MAX {
		path.stages[path.count] = stage
		path.count += 1
	}
}

// Unit test builds only: the push for `stage` must come from the function
// and file STEP_STAGES gives for it, so a renamed or moved function fails
// the tests instead of showing a stale name in the debugger.
@(private = "file")
step_path_check :: proc(stage: Step_Stage, location: runtime.Source_Code_Location) {
	info := STEP_STAGES[stage]
	assert(location.procedure == info.procedure, "step_path_push: the stage doesn't name the function it is pushed from")
	file := location.file_path
	assert(len(file) >= len(info.file) && file[len(file) - len(info.file):] == info.file, "step_path_push: STEP_STAGES has the wrong file for this stage")
}
