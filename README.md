# Hummingbird Fluent

Hummingbird interface to the [Fluent](https://github.com/vapor/fluent-kit) database ORM.

Hummingbird doesn't come with any database drivers or ORM. This library provides a connection to Vapor's database ORM. The Vapor guys have been generous and forward thinking enough to ensure Fluent-kit can be used independent of Vapor. They have a small library that links Vapor to Fluent, this library does pretty much the same thing for Hummingbird.

## Usage

The following initializes an SQLite database and adds a single migration `CreateTodo`.

```swift
import FluentSQLiteDriver
import HummingbirdFluent

let app = HBApplication()
// add Fluent
app.addFluent()
// add sqlite database
app.fluent.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
// add migrations
app.fluent.migrations.add(CreateTodo())
// migrate
if arguments.migrate {
    try app.fluent.migrate().wait()
}
```
In general the interface to Fluent follows the same pattern as Vapor, except the `db` and `migrations` objects are only accessible from within the `fluent` object, and you need to call `HBApplication.addFluent()` at initialization.

Fluent can be used from a route as follows. The database is accessible via `HBRequest.db`.

```swift
app.router
    .endpoint("todos")
    .get(":id") { request in 
        guard let id = request.parameters.get("id", as: UUID.self) else { return request.failure(HBHTTPError(.badRequest)) }
        return Todo.find(id, on: request.db)
    }
```
Here we are returning a `Todo` with an id specified in the path.
