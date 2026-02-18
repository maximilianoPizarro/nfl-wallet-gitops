# Red Hat Connectivity Link and Service Mesh — Approval Spec

The shift from Red Hat 3scale to the combination of **Red Hat Connectivity Link** (Kuadrant) and **Red Hat Service Mesh (Ambient Mode)** represents a move from a centralized, monolithic API gateway model to a decentralized, Kubernetes-native architecture. Connectivity Link handles North/South traffic and multi-cluster policy; the Service Mesh handles East/West traffic, resiliency, and zero-trust security.

This document defines the **approval and success criteria** for the demo. Each use case below lists what must be demonstrated or verified for acceptance.

---

## 1. Multi-Cluster

- **Must demonstrate** both federated-mesh topologies (e.g. multi-primary) as installed, including which pods are added and how the assembled mesh appears in Kiali.
- **Must show** automatic service discovery: a service deployed in Cluster B appears in the Kiali service map of Cluster A as a remote endpoint.
- **Must show** cross-cluster failover: when all replicas of a given service in Cluster A are scaled to zero, the mesh automatically reroutes 100% of traffic to healthy replicas in Cluster B with sub-second latency impact.
- **Must demonstrate** control plane independence: in a multi-primary setup, Cluster B continues to manage local traffic and security policies when the control plane (istiod) of Cluster A is unavailable.
- **Must provide** a resource overhead comparison (CPU/RAM) showing significant reduction vs. a sidecar-based mesh, with ztunnel handling L4 transport with minimal footprint.
- **Must demonstrate** infrastructure segregation: the platform/infrastructure team can manage the L4 layer (ztunnel) independently of the development team managing the L7 layer (waypoints).

## 2. Security

- **Must demonstrate** namespace A with access completely denied.
- **Must demonstrate** namespace A in cluster 2 with access completely denied.
- **Must show** that this configuration is as centralized as possible (e.g. an OSSM CR that propagates between clusters).
- **Must show** that an AuthorizationPolicy applied in the primary cluster correctly denies or allows traffic to a specific ServiceAccount regardless of which cluster the request originates from.
- **Must verify** a single root CA (shared trust) issues certificates to both clusters, enabling seamless cross-cluster mTLS.
- **Must demonstrate** encryption at rest and in transit: 100% of inter-cluster traffic is encrypted via mTLS by default in Ambient mode without manual certificate injection into application pods.

## 3. Global Service Management (East-West)

- **Must not use** external load balancers or external DNS for internal service-to-service traffic; internal mesh hostnames (e.g. `service-b.namespace.svc.cluster.local`) must be used.
- **Must show** in trace or Kiali what traffic flows from namespace A to namespace B.
- **Must show** the same flow when namespace B is in another cluster, with no traffic leaving the SDN or hitting corporate load balancers.

## 4. Discovery and Service Map

- **Must expose** two services from two namespaces in two different clusters and display them on the Kiali service map.
- **Must show** automatic service discovery: a service deployed in Cluster B appears in the Kiali service map of Cluster A as a remote endpoint.

## 5. API Publication from Swagger

- **Must use** the microservice’s Swagger/OpenAPI spec to derive mapping rules (paths, verbs).
- **Must create** the elements for accessing the API (mapping rules, paths, verbs) and add hostname data to generate the route.
- **Must demonstrate** that the API is callable as described in the use case.

## 6. Subscription and Credential-Based Access

- **Must demonstrate** namespace A able to consume namespace B using credentials, and namespace C denied access due to lack of credentials.
- **Must replicate** a subscription model analogous to 3scale: choice of APIs by name or project acronym, with unique credentials per consumer (e.g. namespace A always uses the same credentials).
- **Must show** that an APP_ID (or equivalent) is read from the client request and passed in a header to the backend.

## 7. Usage Metrics

- **Must provide** traffic inquiry by API and by path.
- **Must provide** metrics by response code and response times.
- **Must identify** who consumes the APIs and their ratios.

## 8. Traceability

- **Must show** the complete communication trace between services in the chosen observability tool (e.g. AppDynamics).
- **Must demonstrate** end-to-end tracing for requests between services.

## 9. mTLS for External Clients

- **Must support** external clients consuming APIs using custom certificates (e.g. organization-issued).
- **Must demonstrate** that the API gateway validates that the certificate for consuming a particular API exists and is correct.

## 10. External Backends

- **Must define** a public external service and control access to it (e.g. via Service Entry or the Kuadrant external API pattern).
- **Must demonstrate** rate limiting where applicable (e.g. for external API consumption).

## 11. Special Ciphers

- **Must identify** an example of a legacy or deprecated cipher.
- **Must connect** a service to TLS that exposes this cipher (e.g. using an image that allows the required legacy encryption).

## 12. Blue/Green

- **Must demonstrate** Blue/Green (or equivalent) capability on published routes, with criteria met as described in the use case.

## 13. Publish APIs Across OCP Clusters and Load Balance from Outside

- **Must demonstrate** that when the API is in the local cluster, traffic does not leave the cluster and does not use external balancers or DNS.
- **Must demonstrate** that when the API is not in the local location, traffic is routed to the correct cluster/location (including edge DNS or equivalent).

---

## Connectivity Link Focus Areas

The approval criteria above cover the following strategy areas for the Connectivity Link demo:

- **API publication (Swagger to Gateway API):** Automated generation of HTTPRoutes from OpenAPI/Swagger, with mapping rules and hostnames.
- **Subscription and security (auth and headers):** AuthPolicy for credentials, fine-grained access by namespace, and header injection (e.g. X-App-Id) to the backend.
- **Metrics and traceability:** Traffic analytics by path, response code, and latency; integration with observability tools and W3C trace context propagation.
- **mTLS and special ciphers:** Client mTLS with custom CA and support for legacy cipher suites where required.
- **Lifecycle (staging, prod, Blue/Green):** Staging vs. production hostnames and weight-based Blue/Green routing on published routes.
