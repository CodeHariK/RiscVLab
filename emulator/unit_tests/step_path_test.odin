package rv_unit_tests

import "core:fmt"
import "core:strings"
import "core:testing"
import rv "../core"

// Unit tests for the step path (core/step_path.odin): which of the
// emulator's functions a step went through, in call order. A test build
// also checks, at every push, that the stage names the function it is
// pushed from (step_path_check), so stepping these instructions checks
// the names too.

@(private = "file")
MRET :: u32(0x3020_0073)
@(private = "file")
ECALL :: u32(0x0000_0073)
@(private = "file")
CSRR_T0_MSTATUS :: u32(0x3000_22f3) // csrrs t0, mstatus, zero
@(private = "file")
S_CODE :: rv.RAM_BASE + 0x100
@(private = "file")
HANDLER :: rv.RAM_BASE + 0x800

// MRET at RAM_BASE into supervisor mode at S_CODE, where `code` waits.
@(private = "file")
machine_with :: proc(code: ..u32) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, 16)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(MRET))
	for instruction, index in code {
		rv.machine_store(&machine, S_CODE + u64(index) * 4, 4, u64(instruction))
	}
	machine.cpu.csr.mepc = S_CODE
	machine.cpu.csr.mtvec = HANDLER
	machine.cpu.csr.mstatus = rv.mstatus_with_mpp(0, .Supervisor)
	return machine
}

@(private = "file")
expect_path :: proc(t: ^testing.T, machine: ^rv.Machine, want: []rv.Step_Stage, location := #caller_location) {
	got := rv.step_path_stages(&machine.cpu.debug_path)
	testing.expectf(t, slice_equal(got, want), "path %v, want %v", got, want, loc = location)
}

@(private = "file")
slice_equal :: proc(a, b: []rv.Step_Stage) -> bool {
	if len(a) != len(b) {
		return false
	}
	for value, index in a {
		if value != b[index] {
			return false
		}
	}
	return true
}

@(test)
step_path_of_mret :: proc(t: ^testing.T) {
	machine := machine_with(NOP)
	defer rv.machine_destroy(&machine)

	rv.machine_step(&machine)
	expect_path(t, &machine, {.Machine_Step, .Cpu_Step, .Execute, .Exec_System, .Exec_Mret})
}

@(test)
step_path_is_cleared_each_step :: proc(t: ^testing.T) {
	machine := machine_with(NOP) // addi zero, zero, 0
	defer rv.machine_destroy(&machine)

	rv.machine_step(&machine) // mret
	rv.machine_step(&machine) // the nop
	expect_path(t, &machine, {.Machine_Step, .Cpu_Step, .Execute, .Exec_Op_Imm})
}

@(test)
step_path_of_an_ecall_up_to_machine_mode :: proc(t: ^testing.T) {
	machine := machine_with(ECALL)
	defer rv.machine_destroy(&machine)

	rv.machine_step(&machine) // mret
	rv.machine_step(&machine) // ecall: Ecall_From_S_Mode, not delegated
	expect_path(t, &machine, {
		.Machine_Step, .Cpu_Step, .Execute, .Exec_System,
		.Trap_Target, .Trap_Enter, .Trap_Enter_Machine,
	})
}

@(test)
step_path_of_an_illegal_csr_access :: proc(t: ^testing.T) {
	machine := machine_with(CSRR_T0_MSTATUS) // mstatus is machine only
	defer rv.machine_destroy(&machine)

	rv.machine_step(&machine) // mret
	rv.machine_step(&machine) // csrr: Illegal_Instruction, the longest path
	expect_path(t, &machine, {
		.Machine_Step, .Cpu_Step, .Execute, .Exec_System, .Exec_Zicsr,
		.Trap_Target, .Trap_Enter, .Trap_Enter_Machine,
	})
}

// Every stage's function name is its enum name in lower case, and every
// file is in core/: the table stays in step with Step_Stage.
@(test)
step_stage_names_match_their_functions :: proc(t: ^testing.T) {
	for info, stage in rv.STEP_STAGES {
		name := strings.to_lower(fmt.tprint(stage), context.temp_allocator)
		testing.expectf(t, info.procedure == name, "%v: procedure %q", stage, info.procedure)
		testing.expectf(t, strings.has_prefix(info.file, "core/"), "%v: file %q", stage, info.file)
		// Following callers from any stage reaches machine_step, the root.
		at, hops := stage, 0
		for at != .Machine_Step && hops <= len(rv.Step_Stage) {
			at = rv.STEP_STAGES[at].parent
			hops += 1
		}
		testing.expectf(t, at == .Machine_Step, "%v: its callers never reach machine_step", stage)
	}
}
