import Foundation

let config = Config.fromEnvironment()
let bot = Bot(config: config)

Task {
    await bot.run()
}

RunLoop.main.run()
