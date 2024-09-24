<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/hummingbird-project/hummingbird/assets/9382567/48de534f-8301-44bd-b117-dfb614909efd">
  <img src="https://github.com/hummingbird-project/hummingbird/assets/9382567/e371ead8-7ca1-43e3-8077-61d8b5eab879">
</picture>
</p>  
<p align="center">
<a href="https://swift.org">
  <img src="https://img.shields.io/badge/swift-5.9-brightgreen.svg"/>
</a>
<a href="https://github.com/hummingbird-project/hummingbird-fluent/actions?query=workflow%3ACI">
  <img src="https://github.com/hummingbird-project/hummingbird-fluent/actions/workflows/ci.yml/badge.svg?branch=main"/>
</a>
<a href="https://discord.gg/7ME3nZ7mP2">
  <img src="https://img.shields.io/badge/chat-discord-brightgreen.svg"/>
</a>
</p>

# Hummingbird Fluent

Hummingbird interface to the [Fluent](https://github.com/vapor/fluent-kit) database ORM.

Hummingbird doesn't come with any database drivers or ORM. This library provides a connection to Vapor's database ORM. The Vapor folks have been generous and forward thinking enough to ensure FluentKit can be used independent of Vapor. This package collates the Fluent features into one. It also provides a driver for the Hummingbird Persist framework.

## Usage

The following initializes an SQLite database and adds a single migration `CreateTodo`.

```swift
import FluentSQLiteDriver
import HummingbirdFluent

let logger = Logger(label: "MyApp")
let fluent = Fluent(logger: logger)
// add sqlite database
fluent.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
// add migration
await fluent.migrations.add(CreateTodo())
// migrate
if arguments.migrate {
    try fluent.migrate().wait()
}
```

Fluent can be used from a route as follows.

```swift
let router = Router()
router
    .group("todos")
    .get(":id") { request, context in 
        guard let id = context.parameters.get("id", as: UUID.self) else { return request.failure(HTTPError(.badRequest)) }
        return Todo.find(id, on: fluent.db())
    }
```
Here we are returning a `Todo` with an id specified in the request URI.

You can then bring this together by creating an application that uses the router and adding fluent to its list of services

```swift
var app = Application(router: router)
// add the fluent service to the application so it can manage shutdown correctly
app.addServices(fluent)
try await app.runService()
```

## Documentation

Reference documentation for HummingbirdFluent can be found here [here](https://docs.hummingbird.codes/2.0/documentation/hummingbirdfluent) and you can find more documentation on Fluent [here](https://docs.vapor.codes/4.0/fluent/overview/).
