--- Compatibility shim for the pre-split module name.
---
--- `laze.extras` is the canonical path; this file only keeps existing
--- `require("laze.extra")` configs working and can be deleted once the
--- singular name is retired.
return require("laze.extras")
