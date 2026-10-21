import { execFileSync } from "node:child_process"
import { existsSync, readdirSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const root = join(homedir(), ".claude", "plugins", "cache", "devkit", "commentie")

function compareVersions(a, b) {
  const pa = a.split(".").map(Number)
  const pb = b.split(".").map(Number)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const difference = (pa[i] ?? 0) - (pb[i] ?? 0)
    if (difference !== 0) return difference
  }
  return 0
}

function newestVersion() {
  if (!existsSync(root)) return null
  const versions = readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^\d+(\.\d+)*$/.test(entry.name))
    .map((entry) => entry.name)
    .sort(compareVersions)
  return versions.at(-1) ?? null
}

function commentieSkills() {
  const version = newestVersion()
  if (!version) return null
  const path = join(root, version, "skills")
  return existsSync(path) ? path : null
}

function checkComments(filePath, cwd) {
  const script = join(cwd, "tool", "check_comments.py")
  if (!existsSync(script)) return null
  const payload = JSON.stringify({ tool_input: { file_path: filePath }, cwd })
  for (const python of ["python", "python3"]) {
    try {
      const stdout = execFileSync(python, [script, "--hook"], {
        cwd,
        input: payload,
        encoding: "utf8",
        env: {
          ...process.env,
          CLAUDE_PLUGIN_OPTION_HOOK_ENABLED: "true",
          PYTHONIOENCODING: "utf-8",
        },
        stdio: ["pipe", "pipe", "ignore"],
        timeout: 15000,
      })
      return stdout.trim()
    } catch (error) {
      if (error.code !== "ENOENT") return null
    }
  }
  return null
}

function additionalContext(raw) {
  if (!raw) return null
  try {
    return JSON.parse(raw)?.hookSpecificOutput?.additionalContext ?? null
  } catch {
    return null
  }
}

export const CommentieBridge = async ({ worktree }) => ({
  config: async (config) => {
    const path = commentieSkills()
    if (!path) return
    if (Array.isArray(config.skills)) {
      if (!config.skills.includes(path)) config.skills.push(path)
      return
    }
    config.skills = config.skills ?? {}
    config.skills.paths = config.skills.paths ?? []
    if (!config.skills.paths.includes(path)) config.skills.paths.push(path)
  },

  "tool.execute.after": async (input, output) => {
    if (input.tool !== "edit" && input.tool !== "write") return
    const filePath = input.args?.filePath
    if (!filePath) return
    const note = additionalContext(checkComments(filePath, worktree))
    if (note) output.output += `\n\n${note}`
  },
})
