# Hummingbird Fluent

Hummingbird interface to the [Fluent](https://github.com/vapor/fluent-kit) database ORM.

Hummingbird doesn't come with any database drivers or ORM. This library provides a connection to Vapor's database ORM. The Vapor guys have been generous and forward thinking enough to ensure Fluent-kit can be used independent of Vapor. This package collates the fluent features into one. It also provides a driver for the Hummingbird Persist framework.

## Usage

The following initializes an SQLite database and adds a single migration `CreateTodo`.

```swift
import FluentSQLiteDriver
import HummingbirdFluent

let logger = Logger(label: "MyApp")
let fluent = HBFluent(logger: logger)
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
let router = HBRouter()
router
    .group("todos")
    .get(":id") { request, context in 
        guard let id = context.parameters.get("id", as: UUID.self) else { return request.failure(HBHTTPError(.badRequest)) }
        return Todo.find(id, on: fluent.db())
    }
```
Here we are returning a `Todo` with an id specified in the request URI.

You can then bring this together by creating an application that uses the router and adding fluent to its list of services

```swift
var app = HBApplication(router: router)
// add the fluent service to the application so it can manage shutdown correctly
app.addServices(fluent)
try await app.runService()
```

You can find more documentation on Fluent [here](https://docs.vapor.codes/4.0/fluent/overview/).
