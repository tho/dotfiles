# Architecture decisions

Produce boundaries a maintainer can explain through responsibilities and import direction. Preserve the project's established architecture unless the requested change exposes a concrete problem with it.

## Choose from pressures, not size

| Approach | Pressure it addresses | Cost to justify |
| --- | --- | --- |
| Flat or feature packages | A cohesive application with few independently changing boundaries | Watch for mixed responsibilities as requirements grow |
| Clean architecture | Business policy must remain independent of transport and persistence | Extra translation and layers; inner packages must not import outer adapters |
| Hexagonal architecture | Several entry points or external implementations share the same application behavior | Explicit ports and adapter wiring; a port need not be an interface if a concrete API suffices |
| Domain-driven design | Rich invariants, domain language, and distinct consistency or ownership boundaries | Modeling work and cross-context translation; DDD can coexist with clean or hexagonal architecture |

Directory names do not enforce these properties. Trace imports and caller behavior. Prefer feature boundaries over a universal service/repository layer when features change independently. A package named shared or utils needs a coherent responsibility, not merely several importers.

Put interface contracts near their consumers when that preserves dependency direction. Do not force all interfaces into a central ports package or make implementations import consumers solely to declare satisfaction. A library may intentionally publish an extension interface for external implementers.

## Invariants and domain boundaries

Identify which operations must succeed atomically before choosing aggregate boundaries. An aggregate's methods preserve its invariants on both success and failure; validate a proposed mutation before committing it to in-memory state. Transport validation cannot replace checks on domain operations callable through other entry points.

Entities carry identity; value objects represent values. Go structs containing slices, maps, or pointers are not automatically immutable or deeply comparable. Define copying and equality according to the domain.

Bounded contexts own their models and translate at explicit boundaries. Do not create a shared domain type merely because two contexts currently use similar fields. An in-process package boundary does not imply a separate service or module.

Persistence followed by event publication or a remote payment is not one atomic operation. If failure between them matters, name the consistency requirement and a suitable mechanism such as an outbox, idempotency, or compensation.

## Existing code

Map the dependency cycle or change pressure before proposing layers; `go list -f '{{.ImportPath}}: {{join .Imports " "}}' ./...` shows the actual import direction. An interface at the consuming boundary, a small neutral value package, or relocating orchestration may remove a cycle; a grab-bag shared package merely hides it.

The useful result is a dependency direction, ownership decisions, and enough representative signatures or wiring to demonstrate that the boundaries work. A full project tree or an ADR is optional unless requested.
