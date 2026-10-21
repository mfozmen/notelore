import { join } from "node:path"

const envFile = /(?:^|[\\/\s"'=])\.env(?:\.[A-Za-z0-9_-]+)*(?=$|[\s"'\\/;:])/i
const envExample = /(?:^|[\\/\s"'=])\.env\.example(?=$|[\s"'\\/;:])/i
const dartDefine = /--dart-define-from-file[=\s]+\S*\.env(?:\.[A-Za-z0-9_-]+)?/i

function segments(command) {
  return command
    .split(/[;&|\n]/)
    .map((segment) => segment.trim())
    .filter(Boolean)
}

function tokens(segment) {
  return (segment.match(/"[^"]*"|'[^']*'|\S+/g) ?? []).map((token) =>
    token.replace(/^(['"])(.*)\1$/, "$2"),
  )
}

function readsEnv(command) {
  return segments(command).some((segment) => {
    if (!envFile.test(segment)) return false
    return !envExample.test(segment) && !dartDefine.test(segment)
  })
}

function forcePushes(command) {
  return segments(command).some((segment) => {
    const parts = tokens(segment)
    let index = 0
    while (index < parts.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(parts[index])) index++
    if (parts[index] !== "git") return false
    index++
    const takesArg = new Set([
      "-C",
      "-c",
      "--git-dir",
      "--work-tree",
      "--namespace",
      "--exec-path",
      "--config-env",
    ])
    while (index < parts.length && parts[index].startsWith("-")) {
      index += takesArg.has(parts[index]) ? 2 : 1
    }
    if (parts[index] !== "push") return false
    return parts.slice(index + 1).some(
      (part) =>
        part === "--force" ||
        part === "--force-with-lease" ||
        part === "--force-if-includes" ||
        part.startsWith("--force=") ||
        part.startsWith("--force-with-lease=") ||
        part.startsWith("--force-if-includes=") ||
        /^-[A-Za-z]*f[A-Za-z]*$/.test(part) ||
        part.startsWith("+"),
    )
  })
}

export const NoteloreEnv = async ({ worktree }) => {
  const home = join(worktree, ".dev-home")

  return {
    "shell.env": async (_input, output) => {
      if (!output.env.NOTELORE_HOME && !process.env.NOTELORE_HOME) {
        output.env.NOTELORE_HOME = home
      }
    },
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash" && input.tool !== "shell") return
      const command = output.args?.command
      if (typeof command !== "string") return
      if (readsEnv(command)) {
        throw new Error(
          "Reading .env is blocked. Use .env.example, or ask the maintainer for the value.",
        )
      }
      if (forcePushes(command)) {
        throw new Error("Force-pushing is blocked. Push a normal commit and open a PR.")
      }
    },
  }
}
