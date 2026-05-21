-module(erlmcp_model).

-opaque request() :: map().
-opaque response() :: map().
-opaque notification() :: map().

-export_type([request/0, response/0, notification/0]).
