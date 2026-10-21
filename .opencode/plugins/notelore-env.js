import { join } from "node:path"

export const NoteloreEnv = async ({ worktree }) => {
  const home = join(worktree, ".dev-home")

  return {
    "shell.env": async (_input, output) => {
      if (!output.env.NOTELORE_HOME && !process.env.NOTELORE_HOME) {
        output.env.NOTELORE_HOME = home
      }
    },
  }
}
