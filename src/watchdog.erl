%%% File    : watchdog.erl
%%% Author  : Rudolph van Graanx
%%% Description : Use this utils module for code that 

-module(watchdog).


-define(CALLTIMEOUT,5000).
-define(WATCHDOG_WAIT,10000).

-record(state,{owner,
	       id,
	       monitor,
	       timeout,
	       grace_counter = 3,
	       counter = 3}).

-export([start/2,
	 reset/1,
	 init/1]).

start(ID,Timeout) when is_integer(Timeout) ->
  Owner = self(),
  process_flag(save_calls, 40),
  PID = proc_lib:spawn_link(?MODULE,init,[[Owner,ID,Timeout]]),
  {ok,PID}.


reset(PID) ->
  Ref = make_ref(),
  PID ! {watchdog_reset,self(),Ref},
  receive 
    {watchdog_ack,Ref} ->
      ok
  after
    ?CALLTIMEOUT ->
      {error,timeout}
  end.


init([Owner,ID,Timeout]) ->
  process_flag(trap_exit,true),
  Monitor = erlang:monitor(process,Owner),
  run_loop(#state{owner   = Owner,
		  id      = ID,
		  monitor = Monitor,
		  timeout = Timeout}).


run_loop(State) ->
  receive
    {watchdog_reset,PID,Ref} ->
      PID ! {watchdog_ack,Ref},
      run_loop(State#state{counter = State#state.grace_counter});
    {'DOWN', _Monitor , process, _Owner, _Info} ->
      normal
  after
    State#state.timeout -> 
      if
	State#state.counter > 0 ->
	  run_loop(State#state{counter = State#state.counter -1});
	State#state.counter =< 0 ->
	  timeout(State)
      end
  end.

timeout(State) ->
  LastCalls             = process_info(State#state.owner, last_calls),
  CurrentFunction       = process_info(State#state.owner, current_function),
  {backtrace,BackTrace} = process_info(State#state.owner, backtrace),
  error_logger:error_report(["Watchdog timeout condition detected",
			     "Process will now be killed",
			     {id,State#state.id},
			     {pid,State#state.owner},
			     CurrentFunction,{backtrace,string:tokens(binary_to_list(BackTrace),[10])},LastCalls]),
  exit(State#state.owner,kill),
  receive 
    {'DOWN', _Monitor , process, _Owner, _Info} ->
      normal
  end.

  
