# General Requirements #

1. The service must:
  - Expose CRUD endpoints in proper REST style.
  - Use port 8000 and address 127.0.0.1 unless otherwise provided by the command line.
  - Support API versioning via the Accept request header and return the version via the Content-Type response header.
  - Follow the behaviors for version negotiation:
    - Return 406 Not Acceptable if no version specified.
    - Return 200 OK if a valid version is requested.
    - Return 406 Not Acceptable for invalid versions.
    - Return 410 Gone for removed versions.
    - Set Deprecation header (RFC 9651 date as Unix timestamp) if the version is deprecated. (Epoch is 1970-01-91T00:00:00 UTC).
    - Set Sunset header (RFC 7231 HTTP-date) if the version is deprecated and removal is scheduled.
  - In the example services version 0 has been removed, version 1 is deprecated, and version 2 is current.

2. The service must be modular and split across multiple files according to best practices for the specified language.
  - Maintain separate resource models and resource handlers from the generic HTTP/HTTPS request handler.
  - It should be easily possible to support more than once version at once.
  - Provide a clear entrypoint file that starts the HTTP/HTTPS server.

3. CRUD operations should be implemented against a resource named message with the following endpoints:
  - `POST /message` --> Create a new message.
  - `GET /message` --> Retrieve all messages. Paginate to 10 per page.
  - `GET /message/{id}` --> Retrieve a specific message by ID.
  - `PUT /message/{id}` --> Fully update a message.
  - `PATCH /message/{id}` --> Partially update a message.
  - `DELETE /message/{id}` --> Delete a message.

4. Each endpoint must:
  - Use appropriate HTTP status codes.
  - Return structured JSON responses.
  - Handle errors gracefully with informative messages.
  - Include request/response validation where applicable.
  - Paginate if providing more than 10 elements by providing a `previous` and `next` id/timestamp.

5. Assume a simple in-memory data store for messages:
  - Ensure the data store is modularly separated with simple functions to create, read, update, and delete elements from the store.
  - Ensure the design could be replaced with an SQL database easily in future.
  - The structure of a message is:
  ```python
    id: int      # Unique id of the message.
    author: str  # String author name.
    content: str # String content of the message
    created: int # 64bit timestamp in nanoseconds, epoch is 1970-01-91T00:00:00 UTC.
    updated: int # 64bit timestamp in nanoseconds, epoch is 1970-01-91T00:00:00 UTC.
  ```

# Implementation Guidelines #

- Use the specified language.
- Follow idiomatic best practices for that language and ecosystem.
- Avoid any third-party dependencies unless explicitly part of the service type (e.g., FastAPI for Python).
- Structure the code so it can be run via the following commands (aligned with the project's pixi setup):
  ```shell
  pixi install
  pixi run service
  ```

# Deliverables #

- Provide the full source code, separated into multiple files as appropriate.
- Include comments explaining design choices, especially around version handling and REST conventions.
- Ensure the code is production-ready, clean, and consistent with the project README.
