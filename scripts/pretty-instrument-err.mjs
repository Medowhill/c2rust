#!/usr/bin/env node

/**
 * Consume output from `c2rust instrument` (which invokes `cargo`)
 * and pretty print it.
 * 
 * For example, `cargo` prints lots of JSONL messages,
 * so we parse those and print their `rendered` fields if they have them,
 * which are colored and pretty-printed already.
 * 
 * Stack traces we leave alone.
 */

import * as fs from "fs";

const [_nodePath, _scriptPath, ...args] = process.argv;
let stderr = fs.readFileSync("/dev/stdin").toString(); // jsonl
stderr = stderr.split("\n")
    .map(line => {
        try {
            return JSON.parse(line);
        } catch {
            // probably a stacktrace
            return {
                level: "error: internal compiler error",
                message: line,
                rendered: line,
            };
        }
    })
    .filter(e => (e.level || "").includes("error"))
    .map(e => e.rendered ? e.rendered : e.message) // okay if `e.rendered === ""`
    .join("\n")
    ;
console.error(stderr);
