# Link to complete work

First establish that the intended program is active. Hardware identification over a control bus can succeed while the network link is down. With Link Up, inspect the relevant interface/address/route and packet capture before blaming an application parser. A host import, blocked output-capture wrapper, occupied socket or wrong destination can resemble missing traffic.

Use current driver/BSP data to identify reset/negotiation and patch requirements. A processing-system MAC may be configured inside the processing-system IP rather than a separate programmable-logic MAC block. Source edits must propagate through generated libraries and the running image.

Define framing/version, byte order, geometry/lengths, packet count/index, final packet size and integrity. Bound copies before writing shared storage. Highest packet index is not proof of a full set. Expire incomplete input and prevent late packets from resurrecting a rejected generation; account for sequence wrap and reset.

Keep receiving, ready and processing ownership separate. A latest-frame policy may replace eligible unprocessed work, never an active consumer's storage. A result retains the original source identity even after new arrivals. Distinguish deliberate admission drops, transport corruption and processed-but-wrong outputs.

Inspect how much a driver input call actually services and how long processing blocks it. Bounded batch drain, timely READY publication, packet pacing, pre-encoding or schedule rebasing can help a demonstrated burst problem; a larger ring alone cannot fix invalid admission or unsafe reuse. Do not let an infinite drain starve processing/recovery.

For TX reference buffers, preserve memory and cache visibility through actual completion, not only the API call. Compare against a known-correct copying path. Inspect MTU/headers, pbuf or socket behavior, descriptor reclamation and bounded retry. Verify the installed implementation rather than assuming one network stack or OS.

Inject missing/corrupt/duplicate/delayed packets only in an authorized isolated test and assert no partial input enters processing. Report measured send rate rather than the request, per-window deltas rather than unlabeled cumulative counters, and separate host transaction time from processing time.
