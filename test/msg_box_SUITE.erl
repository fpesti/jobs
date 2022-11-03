-module(msg_box_SUITE).
-compile([export_all, nowarn_export_all]).
%-export([start_test_server/1]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-define(QUEUE_CONFIG,                                                               
      [{path_restart, [{standard_counter, 100}]},                          
      {create, [{max_size, 1000}, {regulators, [{rate, [{limit, 400}]}]}]},
      {delete, [{max_size, 1000}, {regulators, [{rate, [{limit, 400}]}]}]},
      {other, [{ max_size, 1000}, {regulators, [{rate, [{limit, 400}]}]}]} 
      ]).
-define(QUEUE_NAMES, [path_restart, create, delete, other]).                                                               

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
				  Res = jobs:add_queue(Name, Options)
		 end, ?QUEUE_CONFIG).

remove_queues()->
   lists:foreach(fun({Name, _})-> jobs:remove_queue(Name) end, ?QUEUE_CONFIG).

msg_box_test(_Config)->
   Rate = 1000,
   Test_Interval = 10000000,
   generate_jobs(Rate, Test_Interval),
   ok.

generate_jobs(Rate, Test_Interval)->
   Interval = round(1000/Rate),
   Start_TS = erlang:timestamp(),
   {ok, TRef} = timer:apply_interval(Interval, ?MODULE, start_job, [test_job, Start_TS, Test_Interval, self()]),
   receive 
	expired->
	   timer:cancel(TRef)
   end.

start_job(Job_fun, Start_TS, Interval, Pid)->
    Current_TS = erlang:timestamp(), 
    Elapsed = timer:now_diff(Current_TS, Start_TS),
    QueueName = lists:nth(rand:uniform(length(?QUEUE_NAMES)), ?QUEUE_NAMES),
    %io:format(standard_error, "start_job ~p~n", [QueueName]),
    if (Elapsed < Interval) ->
    	case jobs:ask(QueueName) of 
	    {ok, Opaque}->
    		apply(?MODULE, Job_fun, []),
		jobs:done(Opaque);
	    _->
		ct:pal("Job is rejected !")
    	end;

       true->
	       Pid ! expired
    end.
	

test_job(Max_Sleep_Interval)-> 
    Sleeptime = rand:uniform(Max_Sleep_Interval),
    timer:sleep(Sleeptime). 

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
