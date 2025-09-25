# services #

This project is a collection of [HTTP](# "Hypertext Transfer Protocol")/[HTTPS](# "Hypertext Transfer Protocol Secure") services that perform [CRUD](# "Create Read Update Delete") operations on data in [REST](# "Representational State Transfer") style.

## Services ##

### Raw Services ###

These services use no third-party dependencies:

- [ ] [C](services/c-raw)
- [ ] [C++](services/cpp-raw)
- [ ] [Go](services/go-raw)
- [ ] [Java](services/java-raw)
- [ ] [Php](services/php-raw)
- [ ] [Python](services/python-raw)
- [ ] [R](services/r-raw)
- [ ] [Ruby](services/ruby-raw)
- [ ] [Rust](services/rust-raw)
- [ ] [Zig](services/zig-raw)

### Library Services ###

These services use a helper library to simplify things:

- [ ] [Bash (netcat)](services/bash-netcat)
- [ ] [Java (spring-boot)](services/java-spring-boot)
- [ ] [JavaScript (nodejs)](services/javascript-nodejs)
- [ ] [Python (fast-api)](services/python-fastapi)
- [ ] [Python (django)](services/python-django)

### Running and Dependencies ###

Dependencies of each service are managed using [pixi](https://pixi.sh/) to enable repeatable builds.

Once [pixi](https://pixi.sh/) is installed launching a service should be as simple as:

```shell
cd $SERVICE_NAME
pixi install
pixi run service
```

### Testing ###

To test the services utilise the `test.sh` script. The test script will use pixi to install and launch each service in turn and make a series of requests to ensure the example messages api is being fully handled.

### [API](# "Application Programming Interface") Versioning ###

[URL](# "Uniform Resource Locator") paths are **not** versioned. Version is requested using the `Accept` header and returned using the `Content-Type` header.

- If not provided with a version the behaviour is to fail with a 406 (Not Acceptable).
- For valid specified versions the return code is 200 (OK).
- For invalid versions the return code is 406 (Not Acceptable).
- For removed versions the return code is 410 (Gone).
- For deprecated versions the `Deprecation` header is set with a RFC 9651 Date expressed as a Unix timestamp, e.g. `@1743551999`.
- For deprecated versions with a known removal date the `Sunset` header is also set with a RFC 7231 HTTP-date, e.g. `Tue, 1 Apr 2025 23:59:59 UTC`.

## What is this? ##

### What is [HTTP](# "Hypertext Transfer Protocol")/[HTTPS](# "Hypertext Transfer Protocol Secure")? ###

[HTTP](# "Hypertext Transfer Protocol") is a protocol used for communication between computers over the internet.

[HTTPS](# "Hypertext Transfer Protocol Secure") is [HTTP](# "Hypertext Transfer Protocol") transported over [TLS](# "Transport Layer Security"), which provides encryption, authentication, and integrity.

#### Anatomy of an [HTTP](# "Hypertext Transfer Protocol") Request ####

An HTTP request typically contains:

- **Method** - the action to perform (`POST`, `GET`, `PUT`, `PATCH`, `DELETE`).
- **[URL](# "Uniform Resource Locator")** - the resource being accessed (e.g: `/message`).
- **Headers** - metadata about the request (e.g: `Accept`, `Content-Type`, `Authorization`).
- **Body** (optional) - data sent with the request (common with `POST`, `PUT`, and `PATCH`).


Example request:
```
GET /message HTTP/1.1
Host: example.com
Accept: application/json; version=1
```

#### Anatomy of an [HTTP](# "Hypertext Transfer Protocol") Response ####

An HTTP response usually contains:

- **Status line** - includes the status code (e.g: `200 OK`, `404 Not Found`, `406 Not Acceptable`, `410 Gone`).
- **Headers** - metadata (e.g: `Content-Type`, `Authorization`, `Deprecation`, `Sunset`).
- **Body** - the data returned (e.g: often [JSON](# "JavaScript Object Notation") in the case of [API](# "Application Programming Interface")s).

Example response:
```
HTTP/1.1 200 OK
Content-Type: application/json; version=1

{
    "timestamp": "2025-04-01T23:59:59.999+0000",
    "message":"OK",
}
```

### What is [CRUD](# "Create Read Update Delete")? ###

[CRUD](# "Create Read Update Delete") refers to the four basic operations your software should be able to perform: Create, Read, Update, and Delete.

Users of your such software will be able to **create** data by submitting it in some form, access the data by **reading** it out perhaps in a [UI](# "User Interface"), **update** or edit the data, and finally **delete** the data from the service.

[CRUD](# "Create Read Update Delete") applications/services often consist of four parts: a [UI](# "User Interface"), an [API](# "Application Programming Interface"), some backend code, and a database.

The [UI](# "User Interface") simplifies interaction with the application/service allowing complex queries or representations of data, the [API](# "Application Programming Interface") contains the endpoints that can be used to interact with the backend, the backend contains the code to perform operations, and the database efficiently stores data for reading, writing, updating, and deleting.

Each letter in the [CRUD](# "Create Read Update Delete") acronym has a corresponding [HTTP](# "Hypertext Transfer Protocol")/[HTTPS](# "Hypertext Transfer Protocol Secure") method. There is also a corresponding [SQL](# "Structured Query Language") statment that we may use for each case with the database.

#### [CRUD](# "Create Read Update Delete") Operations ####

| CRUD Operation | HTTP Method     | SQL Statement                 | Description                                                             |
|:---------------|:----------------|:------------------------------|:------------------------------------------------------------------------|
| Create         | `POST`          | `INSERT INTO t(c) VALUES (v)` | Create/Write data to the service.                                       |
| Read           | `GET`           | `SELECT c FROM t`             | Read/Get data from the service.                                         |
| Update         | `PUT` / `PATCH` | `UPDATE t SET c = v WHERE w`  | Update/Set data in the service for PUT (or partially update for PATCH). |
| Delete         | `DELETE`        | `DELETE FROM t WHERE w`       | Delete/Remove data from the service.                                    |

### What is [REST](# "Representational State Transfer")? ###

[REST](# "Representational State Transfer") is an architectural style for building web services on top of [HTTP](# "Hypertext Transfer Protocol")/[HTTPS](# "Hypertext Transfer Protocol Secure").  
It uses simple, stateless communication where resources (such as `message`) are represented by [URL](# "Uniform Resource Locator")s, and actions on those resources are performed using standard [HTTP](# "Hypertext Transfer Protocol") methods.

#### Core Principles of [REST](# "Representational State Transfer") ####

- **Statelessness** - Each request from client to server must contain all the information needed to understand and process it. The server does not store session state between requests.
- **Client-Server Separation** - The client (e.g: browser or other [UI](# "User Interface")) is decoupled from the server, allowing each to evolve independently.
- **Uniform Interface** - Resources are identified by [URL](# "Uniform Resource Locator")s (e.g: `/message`), manipulated through standard [HTTP](# "Hypertext Transfer Protocol") methods, and typically represented in formats such as [JSON](# "JavaScript Object Notation").
- **Resource-Oriented** - Everything in a [REST](# "Representational State Transfer")ful [API](# "Application Programming Interface") is treated as a resource, accessible via a unique [URL](# "Uniform Resource Locator").
- **Stateless Communication** - Caching, authentication, and request handling all rely on self-contained messages.

#### Example [REST](# "Representational State Transfer") Endpoints ####

A [REST](# "Representational State Transfer")ful service managing messages might expose endpoints like:

| Resource Action   | HTTP Method | Example Endpoint | Description                           |
|:------------------|:------------|:-----------------|:--------------------------------------|
| Create message    | `POST`      | `/message`       | Add a new message.                    |
| Read all messages | `GET`       | `/message`       | Retrieve a list of all messages.      |
| Read message      | `GET`       | `/message/{id}`  | Retrieve a specific message.          |
| Update message    | `PUT`       | `/message/{id}`  | Replace a message data completely.    |
| Partial update    | `PATCH`     | `/message/{id}`  | Update only part of a message's data. |
| Delete message    | `DELETE`    | `/message/{id}`  | Remove a message.                     |

## License ##

The MIT License

Copyright (c) 2025 Geoffrey Daniels. http://gpdaniels.com/

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

