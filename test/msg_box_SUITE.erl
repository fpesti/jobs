-module(msg_box_SUITE).
-compile([export_all, nowarn_export_all]).
%-export([start_test_server/1]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-define(QUEUE_CONFIG,                                                               
      [%{path_restart, [{standard_counter, 100}]},                          
      {create, [{max_size, 1000}, {regulators, [{rate, [{limit, 400}]}]}]},
      {delete, [{max_size, 1000}, {regulators, [{rate, [{limit, 400}]}]}]},
      {other, [{ max_size, 1000}, {regulators, [{rate, [{limit, 400}]}]}]} 
      ]).
-define(QUEUE_NAMES, [create, delete, other]).                                                               

suite() ->
	[{timetrap,{seconds,30}}].

groups() -> [].

init_per_suite(Config) ->
    ct:pal("Init start ~p~n", [Config]),
    Name = {q, ?LINE},
    Res = start_test_server(false, {Name, [{standard_counter, 1}]}),
    ct:pal("Res: ~p~n", [Res]),
    Config.

end_per_suite(_Config) ->
    stop_server(),
    ok.

all() ->[msg_box_test].

init_per_testcase(msg_box_test, Config)->
    add_queues(),
    Config.
%init_per_testcase(Config) ->
%    ct:pal("Init start3 ~p~n", [Config]),
%    Config.

end_per_testcase(_Config) ->
    remove_queues(),
    ok.

%end_per_testcase(_Config) ->
%    ok.

%%-------------------------------------------------------------


add_queues()->
   lists:foreach(fun({Name, Options})-> 
				  jobs:add_queue(Name, Options)
		 end, ?QUEUE_CONFIG).

remove_queues()->
   lists:foreach(fun({Name, _})-> jobs:remove_queue(Name) end, ?QUEUE_CONFIG).

msg_box_test(_Config)->
   Rate = 2000,  %% 1k request/second
   Test_Interval = 10000000, %% 10 seconds
   generate_jobs(Rate, Test_Interval),
   ok.

generate_jobs(Rate, Test_Interval)->
   {Interval, JobNumber} = if Rate > 1000 ->
	JN = trunc(Rate/1000),
	io:format(standard_error, "JobNumber: ~p~n", [JN]),
	{1, JN};
         true->
	{trunc(1000/Rate), 1}
   end,
	      
   io:format(standard_error, "New job start interval ~p, Multiplier ~p~n", [Interval, JobNumber]),
   Start_TS = erlang:timestamp(),
   {ok, TRef} = timer:apply_interval(Interval, ?MODULE, start_job, [test_job, Start_TS, Test_Interval, JobNumber, self()]),
   {Accepted, Rejected} = receive_loop(TRef, 0, 0),
   io:format(standard_error, "Test result:~nTotal Accepted: ~p~nTotal Rejected: ~p~n", [Accepted, Rejected]).

receive_loop(TRef, Accepted, Rejected)->
   receive 
	   {result, {LastAccepted, LastRejected}}->
		   receive_loop(TRef, Accepted + LastAccepted, Rejected + LastRejected);
	   expired->
	 	 timer:cancel(TRef),
		 {Accepted, Rejected}
   end.
   start_job(_Job_fun, Start_TS, Interval, JobNumber, Pid)->
    Current_TS = erlang:timestamp(), 
    Elapsed = timer:now_diff(Current_TS, Start_TS),
    QueueName = lists:nth(rand:uniform(length(?QUEUE_NAMES)), ?QUEUE_NAMES),
    if (Elapsed < Interval) ->
   	Jobs =lists:seq(1, JobNumber),
	Res = lists:foldl(fun(_Item, {Accepted, Rejected})-> 
    			case jobs:ask(QueueName) of 
	    			{ok, Opaque}->
    					apply(?MODULE, test_job, []),
					jobs:done(Opaque),
					{Accepted + 1, Rejected};
	    			_->
					ct:pal("Job is rejected !"),
					{Accepted, Rejected + 1}
    			end
	    	end, {0,0}, Jobs),
		Pid ! {result, Res};
       	true->
	       Pid ! expired
    end.

	

test_job()-> 
    rand:uniform(1000) / rand:uniform(1000).

start_test_server(Conf) ->
    start_test_server(true, Conf).

start_test_server(Silent, {rate,Rate}) ->
    start_with_conf(Silent, [{queues, [{q, [{regulators,
                                             [{rate,[
                                                     {limit, Rate}]
                                              }]}
                                            %% , {mod, jobs_queue_list}
                                           ]}
                                      ]}
                            ]),
    Rate;
start_test_server(Silent, [{rate,Rate},{group,Grp}]) ->
    start_with_conf(Silent,
		    [{group_rates, [{gr, [{limit, Grp}]}]},
		     {queues, [{q, [{regulators,
				     [{rate,[{limit, Rate}]},
				      {group_rate, gr}]}
				   ]}
			      ]}
		    ]),
    Grp;
start_test_server(Silent, {count, Count}) ->
    start_with_conf(Silent,
		    [{queues, [{q, [{regulators,
                                     [reg({count, Count})]
                                    }]
                               }]
                     }]);
start_test_server(Silent, {timeout, T}) ->
    start_with_conf(Silent,
		    [{queues, [{q, [{regulators,
				     [{counter,[
						{limit, 0}
					       ]}
				     ]},
				    {max_time, T}
				   ]}
			      ]}
		    ]);
start_test_server(Silent, {_Name, [_|_]} = Q) ->
    start_with_conf(Silent, [{queues, [Q]}]);
start_test_server(Silent, [_|_] = Rs) ->
    start_with_conf(Silent,
                    [{queues, [{q,
                                [{regulators, [reg(R) || R <- Rs]}]
                               }]
                     }]).

reg({rate, R}) ->
    {rate, [{limit, R}]};
reg({count, C}) ->
    {counter, [{limit, C}]}.

start_with_conf(Silent, Conf) ->
    application:unload(jobs),
    application:load(jobs),
    [application:set_env(jobs, K, V) ||	{K,V} <- Conf],
    if Silent == true ->
	    error_logger:delete_report_handler(error_logger_tty_h);
       true ->
	    ok
    end,
    application:start(jobs).


stop_server() ->
    application:stop(jobs).
