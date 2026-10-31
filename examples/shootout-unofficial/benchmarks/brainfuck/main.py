#!/usr/bin/env python3

import sys


def compile_program(source):
    commands = "".join(command for command in source if command in "+-<>[].")
    jumps = {}
    stack = []
    for at, command in enumerate(commands):
        if command == "[":
            stack.append(at)
        elif command == "]":
            opening = stack.pop()
            jumps[opening] = at
            jumps[at] = opening
    return commands, jumps


def run_program(commands, jumps, repetitions):
    checksum = 0
    for _ in range(repetitions):
        tape = bytearray(64)
        data = 0
        pc = 0
        while pc < len(commands):
            command = commands[pc]
            if command == "+":
                tape[data] = (tape[data] + 1) & 0xFF
            elif command == "-":
                tape[data] = (tape[data] - 1) & 0xFF
            elif command == ">":
                data += 1
            elif command == "<":
                data -= 1
            elif command == "[" and tape[data] == 0:
                pc = jumps[pc]
            elif command == "]" and tape[data] != 0:
                pc = jumps[pc]
            elif command == ".":
                checksum = (checksum * 33 + tape[data]) & 0xFFFFFFFFFFFFFFFF
            pc += 1
    return checksum


program = compile_program(
    "noise ++++++++[>++++++++<-]>+.+.+.+. ignored"
)
print(run_program(*program, int(sys.argv[1])))
