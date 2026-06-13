import Foundation
#if canImport(Glibc)
import Glibc
setbuf(stdout, nil)
setbuf(stderr, nil)
#endif

let config = Config.fromEnvironment()
let bot = Bot(config: config)

Task {
    await bot.run()
}

RunLoop.main.run()
