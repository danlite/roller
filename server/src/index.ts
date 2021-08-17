import Koa, { Middleware } from 'koa'
import Router from 'koa-router'
import * as directory from './directory'
import cors from '@koa/cors'

const PORT = 8001

const app = new Koa()
const router = new Router()

const index: Middleware = async (ctx) => {
  let res = directory.index()

  const filter = ctx.query.filter
  const filters =
    typeof filter === 'string' ? [filter] : filter !== undefined ? filter : []

  if (filters.length > 0)
    res = res.filter((s) => filters.find((f) => s.includes(f)) !== undefined)

  ctx.body = {
    directory: res,
  }
}

const retrieve: Middleware = async (ctx) => {
  ctx.body = directory.retrieve(ctx.params[0])
}

router.get('/', index)
router.get('/(.*)', retrieve)

app
  .use(cors({ origin: '*' }))
  .use(router.routes())
  .use(router.allowedMethods())
  .listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`)
  })
