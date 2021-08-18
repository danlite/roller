import fs from 'fs'
import * as R from 'ramda'
import Path from 'path'

const isDir = (absolutePath: string) => fs.lstatSync(absolutePath).isDirectory()
const isTable = (absolutePath: string) => absolutePath.endsWith('.yml')

const filesInDir = R.curry((root: string, dir: string): string[] =>
  fs
    .readdirSync(Path.join(root, dir))
    .flatMap((entry) => {
      const rootRelativeEntry = Path.join(dir, entry)
      const absoluteEntry = Path.join(root, rootRelativeEntry)
      return isDir(absoluteEntry)
        ? filesInDir(root, rootRelativeEntry)
        : isTable(absoluteEntry)
        ? rootRelativeEntry.replace(/\.yml$/, '')
        : null
    })
    .filter((x): x is string => x !== null)
)

// export const ROOT = Path.resolve('../../../rolltables-private/tables')
export const ROOT = Path.resolve('../rollables')
const filesInRoot = filesInDir(ROOT)

export const index = () => filesInRoot('/')

export const retrieve = (entry: string): string => {
  entry = entry.replace(/^[\/]+/, '')
  const absoluteEntry = Path.resolve(ROOT, entry)
  if (!absoluteEntry.startsWith(ROOT)) {
    throw new Error(`entry ${absoluteEntry} out of bounds!`)
  }
  return fs.readFileSync(absoluteEntry + '.yml').toString('utf-8')
}
