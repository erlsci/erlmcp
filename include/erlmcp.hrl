%%% MCP Protocol Version
-define(APP_NAME, <<"erlmcp">>).
-define(MCP_VERSION, <<"2025-06-18">>).
%%% Standard JSON-RPC 2.0 Error Codes
-define(JSONRPC_PARSE_ERROR, -32700).
-define(JSONRPC_INVALID_REQUEST, -32600).
-define(JSONRPC_METHOD_NOT_FOUND, -32601).
-define(JSONRPC_INVALID_PARAMS, -32602).
-define(JSONRPC_INTERNAL_ERROR, -32603).
%%% JSON-RPC 2.0 Server Error Range (-32000 to -32099)
%%% These can be used for implementation-defined server errors
-define(JSONRPC_SERVER_ERROR_MIN, -32099).
-define(JSONRPC_SERVER_ERROR_MAX, -32000).
%%% JSON-RPC Protocol Fields
-define(JSONRPC_VERSION, <<"2.0">>).
-define(JSONRPC_FIELD_JSONRPC, <<"jsonrpc">>).
-define(JSONRPC_FIELD_ID, <<"id">>).
-define(JSONRPC_FIELD_METHOD, <<"method">>).
-define(JSONRPC_FIELD_PARAMS, <<"params">>).
-define(JSONRPC_FIELD_RESULT, <<"result">>).
-define(JSONRPC_FIELD_ERROR, <<"error">>).
%%% JSON-RPC Error Object Fields
-define(JSONRPC_ERROR_FIELD_CODE, <<"code">>).
-define(JSONRPC_ERROR_FIELD_MESSAGE, <<"message">>).
-define(JSONRPC_ERROR_FIELD_DATA, <<"data">>).
%%% MCP-Specific Error Codes (using the server error range)
-define(MCP_ERROR_RESOURCE_NOT_FOUND, -32001).
-define(MCP_ERROR_TOOL_NOT_FOUND, -32002).
-define(MCP_ERROR_PROMPT_NOT_FOUND, -32003).
-define(MCP_ERROR_CAPABILITY_NOT_SUPPORTED, -32004).
-define(MCP_ERROR_NOT_INITIALIZED, -32005).
-define(MCP_ERROR_SUBSCRIPTION_FAILED, -32006).
-define(MCP_ERROR_VALIDATION_FAILED, -32007).
-define(MCP_ERROR_TRANSPORT_ERROR, -32008).
-define(MCP_ERROR_TIMEOUT, -32009).
-define(MCP_ERROR_RATE_LIMITED, -32010).
%%% Error Messages (for consistency)
-define(JSONRPC_MSG_PARSE_ERROR, <<"Parse error">>).
-define(JSONRPC_MSG_INVALID_REQUEST, <<"Invalid Request">>).
-define(JSONRPC_MSG_METHOD_NOT_FOUND, <<"Method not found">>).
-define(JSONRPC_MSG_INVALID_PARAMS, <<"Invalid params">>).
-define(JSONRPC_MSG_INTERNAL_ERROR, <<"Internal error">>).
-define(MCP_MSG_RESOURCE_NOT_FOUND, <<"Resource not found">>).
-define(MCP_MSG_TOOL_NOT_FOUND, <<"Tool not found">>).
-define(MCP_MSG_PROMPT_NOT_FOUND, <<"Prompt not found">>).
-define(MCP_MSG_MISSING_URI_PARAMETER, <<"Missing uri parameter">>).
-define(MCP_MSG_MISSING_TOOL_NAME, <<"Missing tool name">>).
-define(MCP_MSG_MISSING_PROMPT_NAME, <<"Missing prompt name">>).
-define(MCP_MSG_CAPABILITY_NOT_SUPPORTED, <<"Capability not supported">>).
-define(MCP_MSG_NOT_INITIALIZED, <<"Server not initialized">>).
%%% Convenience macros for common error responses
-define(ERROR_PARSE, {?JSONRPC_PARSE_ERROR, ?JSONRPC_MSG_PARSE_ERROR}).
-define(ERROR_INVALID_REQUEST, {?JSONRPC_INVALID_REQUEST, ?JSONRPC_MSG_INVALID_REQUEST}).
-define(ERROR_METHOD_NOT_FOUND,
        {?JSONRPC_METHOD_NOT_FOUND, ?JSONRPC_MSG_METHOD_NOT_FOUND}).
-define(ERROR_INVALID_PARAMS, {?JSONRPC_INVALID_PARAMS, ?JSONRPC_MSG_INVALID_PARAMS}).
-define(ERROR_INTERNAL, {?JSONRPC_INTERNAL_ERROR, ?JSONRPC_MSG_INTERNAL_ERROR}).
-define(ERROR_RESOURCE_NOT_FOUND,
        {?MCP_ERROR_RESOURCE_NOT_FOUND, ?MCP_MSG_RESOURCE_NOT_FOUND}).
-define(ERROR_TOOL_NOT_FOUND, {?MCP_ERROR_TOOL_NOT_FOUND, ?MCP_MSG_TOOL_NOT_FOUND}).
-define(ERROR_PROMPT_NOT_FOUND, {?MCP_ERROR_PROMPT_NOT_FOUND, ?MCP_MSG_PROMPT_NOT_FOUND}).

%%% MCP Protocol Methods - defined in MCP specification
%%% These constants should be added to erlmcp.hrl

%%% Core Protocol Methods
-define(MCP_METHOD_INITIALIZE, <<"initialize">>).
-define(MCP_METHOD_INITIALIZED, <<"notifications/initialized">>).
%%% Resource Methods
-define(MCP_METHOD_RESOURCES_LIST, <<"resources/list">>).
-define(MCP_METHOD_RESOURCES_READ, <<"resources/read">>).
-define(MCP_METHOD_RESOURCES_TEMPLATES_LIST, <<"resources/templates/list">>).
-define(MCP_METHOD_RESOURCES_SUBSCRIBE, <<"resources/subscribe">>).
-define(MCP_METHOD_RESOURCES_UNSUBSCRIBE, <<"resources/unsubscribe">>).
%%% Tool Methods
-define(MCP_METHOD_TOOLS_LIST, <<"tools/list">>).
-define(MCP_METHOD_TOOLS_CALL, <<"tools/call">>).
%%% Prompt Methods
-define(MCP_METHOD_PROMPTS_LIST, <<"prompts/list">>).
-define(MCP_METHOD_PROMPTS_GET, <<"prompts/get">>).
%%% Sampling Methods (for AI model sampling)
-define(MCP_METHOD_SAMPLING_CREATE_MESSAGE, <<"sampling/createMessage">>).
%%% Notification Methods
-define(MCP_METHOD_NOTIFICATIONS_PROGRESS, <<"notifications/progress">>).
-define(MCP_METHOD_NOTIFICATIONS_RESOURCES_UPDATED, <<"resources/updated">>).
-define(MCP_METHOD_NOTIFICATIONS_RESOURCES_LIST_CHANGED, <<"resources/list_changed">>).
-define(MCP_METHOD_NOTIFICATIONS_PROMPTS_LIST_CHANGED, <<"prompts/list_changed">>).
-define(MCP_METHOD_NOTIFICATIONS_TOOLS_LIST_CHANGED, <<"tools/list_changed">>).
%%% Capability Names - used in capability negotiation
-define(MCP_CAPABILITY_RESOURCES, <<"resources">>).
-define(MCP_CAPABILITY_TOOLS, <<"tools">>).
-define(MCP_CAPABILITY_PROMPTS, <<"prompts">>).
-define(MCP_CAPABILITY_LOGGING, <<"logging">>).
-define(MCP_CAPABILITY_ROOTS, <<"roots">>).
-define(MCP_CAPABILITY_SAMPLING, <<"sampling">>).
%%% Capability Features - used in capability negotiation
-define(MCP_FEATURE_SUBSCRIBE, <<"subscribe">>).
-define(MCP_FEATURE_LIST_CHANGED, <<"listChanged">>).
%%% Content Types
-define(MCP_CONTENT_TYPE_TEXT, <<"text">>).
-define(MCP_CONTENT_TYPE_IMAGE, <<"image">>).
-define(MCP_CONTENT_TYPE_RESOURCE, <<"resource">>).
%%% Message Roles (for prompts)
-define(MCP_ROLE_USER, <<"user">>).
-define(MCP_ROLE_ASSISTANT, <<"assistant">>).
-define(MCP_ROLE_SYSTEM, <<"system">>).
%%% MIME Types - common ones used in MCP
-define(MCP_MIME_TEXT_PLAIN, <<"text/plain">>).
-define(MCP_MIME_APPLICATION_JSON, <<"application/json">>).
-define(MCP_MIME_TEXT_MARKDOWN, <<"text/markdown">>).
%%% Server/Client Info Fields
-define(MCP_INFO_NAME, <<"name">>).
-define(MCP_INFO_VERSION, <<"version">>).
-define(MCP_FIELD_PROTOCOL_VERSION, <<"protocolVersion">>).
-define(MCP_FIELD_CAPABILITIES, <<"capabilities">>).
-define(MCP_FIELD_CLIENT_INFO, <<"clientInfo">>).
-define(MCP_FIELD_SERVER_INFO, <<"serverInfo">>).
%%% Common Parameter Names
-define(MCP_PARAM_URI, <<"uri">>).
-define(MCP_PARAM_NAME, <<"name">>).
-define(MCP_PARAM_ARGUMENTS, <<"arguments">>).
-define(MCP_PARAM_DESCRIPTION, <<"description">>).
-define(MCP_PARAM_MIME_TYPE, <<"mimeType">>).
-define(MCP_PARAM_METADATA, <<"metadata">>).
-define(MCP_PARAM_CONTENT, <<"content">>).
-define(MCP_PARAM_CONTENTS, <<"contents">>).
-define(MCP_PARAM_TEXT, <<"text">>).
-define(MCP_PARAM_DATA, <<"data">>).
-define(MCP_PARAM_TYPE, <<"type">>).
-define(MCP_PARAM_ROLE, <<"role">>).
-define(MCP_PARAM_MESSAGES, <<"messages">>).
-define(MCP_PARAM_RESOURCES, <<"resources">>).
-define(MCP_PARAM_RESOURCE_TEMPLATES, <<"resourceTemplates">>).
-define(MCP_PARAM_TOOLS, <<"tools">>).
-define(MCP_PARAM_PROMPTS, <<"prompts">>).
-define(MCP_PARAM_INPUT_SCHEMA, <<"inputSchema">>).
-define(MCP_PARAM_URI_TEMPLATE, <<"uriTemplate">>).
-define(MCP_PARAM_REQUIRED, <<"required">>).
-define(MCP_PARAM_PROGRESS_TOKEN, <<"progressToken">>).
-define(MCP_PARAM_PROGRESS, <<"progress">>).
-define(MCP_PARAM_TOTAL, <<"total">>).

%%% JSON-RPC Types (records relocated to owning modules in M1-3)
-type json_rpc_id() :: null | binary() | integer().
-type json_rpc_params() :: map() | list() | undefined.

-export_type([json_rpc_id/0, json_rpc_params/0]).
