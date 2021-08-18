import { copySync, mkdirSync, writeFileSync } from 'fs-extra'
import { resolve } from 'path'
import { index, retrieve, ROOT } from '../src/directory'

const ASSETS_DIR = '../client/dist/assets/rollables'

const OUTPUT_DIR = `${ASSETS_DIR}/source`
const INDEX_OUTPUT_FILE = `${ASSETS_DIR}/index.json`
const SINGLE_OUTPUT_FILE = `${ASSETS_DIR}/rollables.json`

async function build() {
  const files = await index()
  const filesWithContents: Array<[string, string]> = await Promise.all(
    files.map(
      async (file): Promise<[string, string]> => [file, await retrieve(file)]
    )
  )
  const contents = new Map<string, string>(filesWithContents)

  writeFileSync(
    SINGLE_OUTPUT_FILE,
    JSON.stringify(Object.fromEntries(contents.entries()))
  )
}

async function buildIndex() {
  writeFileSync(INDEX_OUTPUT_FILE, JSON.stringify(await index()))
  console.log(`✅ Wrote rollable index file into ${resolve(INDEX_OUTPUT_FILE)}`)
}

function copyRollables() {
  copySync(ROOT, OUTPUT_DIR)
  console.log(`✅ Copied rollable YAML files into ${resolve(OUTPUT_DIR)}`)
}

if (require.main === module) {
  mkdirSync(ASSETS_DIR, { recursive: true })
  // build() // unused
  buildIndex()
  copyRollables()
}
