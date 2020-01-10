-module(filog).

%% This  module  enables per-process  and  project-wide
%% logging to files.
%%
%% (This  is  just one  way  of  doing this,  and  just
%% starting to scratch the surface. See
%% https://erlang.org/doc/apps/kernel/logger_chapter.html
%% for the Logger User's Guide.)

-export(
    %% add_handler   {{-
    %%     (HandlerID::atom(), Name::atom())
    %%     -> ok | {error, term()}
    %% ----------------------------------------------------
    %% Set up  a handler to  log to file where  filename is
    %% fixed (at the moment):
    %%
    %% `<NodeName>-<Name>-<Pid>-<Timestamp>`
    %%
    %%   where
    %%   + `Name` is the input atom
    %%     (usually `?MODULE`, except here; see `start/0`)
    %%
    %%   + `Pid` is the calling process
    %%     (which can be different from the process handler
    %%     runs in; see `add_handler_filter/3`)
    %%
    %%   + `Timestamp` is  the number of seconds  since the
    %%     Epoch.
    %% }}-
    [ add_handler/2
    %% Convenience  wrappers  around `add_handler/2`.  Read {{-
    %% `add_handler_filter/3` for the rationale, but in a nutshell:
    %%
    %% + `add_singleton_handler/1` is for registered processes and
    %%
    %% + `add_process_handler/1` is for worker processes without a
    %%    unique name.
    %% }}-
    , add_singleton_handler/1
    , add_process_handler/1
    %% add_handler_filter                               {{-
    %%     (HandlerID::atom(), Name::atom(), Key::term())
    %%     -> ok | {error, term()}
    %% ----------------------------------------------------
    %% Provides the  ability to log events  of each process
    %% into their respective files.
    %%
    %%   where
    %%   + `HandlerID` is ID of the module's log handler
    %%
    %%   + `Name` is an atom to create a unique filter ID
    %%
    %%     (which can be different from the process handler
    %%     runs in; see `add_handler_filter/3`)
    %%
    %%   + `Key` is a term to match on log events
    %%
    %%      When a log handler is set up, all events are sent to
    %%      all handlers [1]. Even  though separate handlers are
    %%      added to each module (and thus, to each process that
    %%      it spawns), every event will end up in all of them.
    %%
    %%      Adding  a filter  to each  handler will  ensure that
    %%      only the  log events that  pertain to a  process (or
    %%      module) get persisted.
    %%
    %%      At first, tried to match on the PID itself, but when
    %%      modules (including behaviours) are started, the init
    %%      function  will  run  way  before the  final  PID  of
    %%      the  `gen_*`  process,  hence  calling  `self()`  in
    %%      `init/1`  and in  the started  `gen_*` process  will
    %%      yield different  result. (Logical, yet I  need to be
    %%      reminded of  it.) In those  cases, a key  other than
    %%      the PID needs to be supplied.
    %%
    %%        + `singleton_handler_filter/2`   is    for   named
    %%          processes where  the key can be  static (such as
    %%          the module or registered name)
    %%
    %%        + `process_handler_filter/2`    is   for    worker
    %%          processes that don't have a unique name.
    %%
    %%          CAVEAT:  Assuming   that  their   init  function
    %%          provides  their final  PID,  and subsequent  log
    %%          events will be matched on `self()`.
    %%
    %% NOTE: Use the same `Key` when issuing logs via `log/3`
    %%       that is used when setting up the filter!
    %%
    %%       For singleton modules/processes,  define a macro
    %%       (e.g., use `Name`  used with `add_handler/1`) or
    %%       use `process_log/2`  for worker  processes, that
    %%       automatically uses  `self()`. (The  caveat above
    %%       applies.)
    %%
    %% [1] This  may  be  an  oversimplification,  because  the
    %%     configuration (primary and handler) has a lot to say
    %%     about  it,  or even  outright  wrong,  but there  is
    %%     probably a kernel of truth in there.
    %% }}-
    , add_handler_filter/3
    %% Convenience wrappers around `add_handler_filter/3`. Read {{-
    %% `add_handler_filter/3` for the rationale
    %% }}-
    , singleton_handler_filter/1
    , process_handler_filter/1
    %% Remove log handler. {{-

    %% NOTE: `Name`  must be  the same  that has  been used
    %%     with `add_handler/1`! Use a macro for example.
    %% }}-
    , remove_singleton_handler/1
    , remove_process_handler/1
    %% log                               {{-
    %%     (Level::atom(), Key::term(), ValueList::list())
    %%     -> ok
    %% ----------------------------------------------------
    %% where
    %%   + `Level` is an atom of
    %%     emergency | alert | critical | error | warning | notice | info | debug
    %%
    %%   + `Key` is the filter term. See `add_handler_filter/3`.
    %%
    %%   + `ValueList` is a list of terms to log.
    %% }}-
    , log/3
    %% process_log(Level::atom(), ValueList::list()) -> ok {{-
    %% ----------------------------------------------------
    %% Convenience wrapper around `log/3` where `Key` == `self()`.
    %% }}-
    , process_log/2
    %% Primary project log {{-
    %% ----------------------------------------------------
    %% Deviating  from  this   project's  conventions,  the
    %% handler is called with  `main` instead of `?MODULE`.
    %% Also,  no filters,  because  this  handler is  added
    %% when  a  node  is   started  (see  Bash  command  in
    %% `call_control.erl`), and any subprocess' log will be
    %% added to it too (hence the name `main`).
    %% }}-
    , start/0
    ]).

%% Reminder:
%% emergency | alert | critical | error | warning | notice | info | debug

start() ->
    logger:set_primary_config(level, debug),
    %% To make less noise on the console:
    %% logger:set_handler_config(default, level, notice),
    add_singleton_handler(main).

add_handler_filter(HandlerID, Name, Key) when is_atom(Name) -> %% {{-
    FilterFun =
        fun
            (#{msg := {report, #{log := [LogKey|_]}}} = LogEvent,
             ProcKey
            ) when LogKey =:= ProcKey ->
                LogEvent;
            (E, P) ->
                erlang:display({E, P}), stop
            % (_, _) -> stop
        end,
    Filter = {FilterFun, Key},
    logger:add_handler_filter(
      HandlerID,
      make_filter_id(Name),
      Filter
    ). %% }}-

singleton_handler_filter(Name) ->
    HandlerID = make_handler_id(Name),
    add_handler_filter(HandlerID, Name, Name).

process_handler_filter(Name) ->
    HandlerID = make_handler_id(Name, self()),
    add_handler_filter(HandlerID, Name, self()).

add_handler(HandlerID, Name) when is_atom(Name) -> %% {{-
    NodeName = atom_to_list(node()),
    Pid = self(),
    % `Timestamp` in Elixir:                           {{-
    % ---------------------------------------------------
    % iex(6)> \
    % :os.timestamp()                                    /
    % |> Tuple.to_list()                                 /
    % |> Enum.reduce("", &(&2 <> Integer.to_string(&1)))
    % #> "1576864416865548"
    % ---------------------------------------------------
    % or simply
    % ---------------------------------------------------
    % iex(7)> DateTime.utc_now() |> DateTime.to_iso8601()
    % #> "2019-12-20T17:53:52.995118Z"
    % ------------------------------------------------}}-
    Timestamp =
        lists:foldl(
            fun(Int, Acc) -> Acc ++ integer_to_list(Int) end,
            "",
            tuple_to_list(os:timestamp())
         ),
    PidString =
        filtered_pid_string(Pid),
    Filename =
        "./" ++
        NodeName           ++ "-" ++
        atom_to_list(Name) ++ "-" ++
        PidString          ++ "-" ++
        Timestamp          ++
        ".log",
    Config =
        #{ config =>
            #{ file  => Filename }
             , level => debug
         },
    logger:add_handler(
      HandlerID,
      logger_std_h,
      Config
    ).
%% }}-

add_singleton_handler(Name) ->
    HandlerID = make_handler_id(Name),
    add_handler(HandlerID, Name).

add_process_handler(Name) ->
    HandlerID = make_handler_id(Name, self()),
    add_handler(HandlerID, Name).

remove_singleton_handler(Name) ->
    HandlerID = make_handler_id(Name),
    logger:remove_handler(HandlerID).

remove_process_handler(Name) ->
    HandlerID = make_handler_id(Name, self()),
    logger:remove_handler(HandlerID).

log(Level, Key, ValueList) when is_list(ValueList) ->
    logger:Level(
        #{ log => [Key | ValueList] }
     ).

process_log(Level, ValueList) ->
    log(Level, self(), ValueList).

%% PRIVATE FUNCTIONS

append(Atom, String) ->
    list_to_atom(
      atom_to_list(Atom) ++ String
    ).

make_handler_id(Name) when is_atom(Name) ->
    append(Name, "_log_handler").

make_handler_id(Name, Pid) when is_pid(Pid) and is_atom(Name) ->
    PidString = filtered_pid_string(Pid),
    NewName = append(Name, PidString),
    make_handler_id(NewName).

make_filter_id(Name) when is_atom(Name) ->
    append(Name, "_log_filter").

filtered_pid_string(Pid) when is_pid(Pid) ->
    lists:filter(
      fun(Elem) -> not(lists:member(Elem, [$<, $>])) end,
      pid_to_list(Pid)
    ).

% vim: set fdm=marker:
% vim: set foldmarker={{-,}}-:
