%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92-*-
%% ex: ts=4 sw=4 et
%% @author James Casey <james@opscode.com>
%% @author Seth Falcon <seth@opscode.com>
%% Copyright 2012 Opscode, Inc. All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%


-module(chef_client_tests).

-include_lib("chef_objects/include/chef_types.hrl").
-include_lib("chef_objects/include/chef_osc_defaults.hrl").
-include_lib("ej/include/ej.hrl").
-include_lib("eunit/include/eunit.hrl").


public_key_data() ->
    {ok, Bin} = file:read_file("../test/spki_public.pem"),
    Bin.

cert_data() ->
    {ok, Bin} = file:read_file("../test/cert.pem"),
    Bin.

osc_assemble_client_ejson_test_() ->
    [{"obtain expected EJSON",
      fun() ->
              Client = #chef_client{name = <<"alice">>,
                                    admin = true,
                                    validator = false,
                                    public_key = public_key_data()},
              {GotList} = chef_client:osc_assemble_client_ejson(Client, ?OSC_ORG_NAME),
              ExpectedData = [{<<"json_class">>, <<"Chef::ApiClient">>},
                              {<<"chef_type">>, <<"client">>},
                              {<<"public_key">>, public_key_data()},
                              {<<"validator">>, false},
                              {<<"admin">>, true},
                              {<<"name">>, <<"alice">>}],
              ?assertEqual(lists:sort(ExpectedData), lists:sort(GotList))
      end},

     {"sets defaults if 'undefined' is encountered",
      fun() ->
              Client = #chef_client{},
              {GotList} = chef_client:osc_assemble_client_ejson(Client, ?OSC_ORG_NAME),
              ExpectedData = [{<<"json_class">>, <<"Chef::ApiClient">>},
                              {<<"chef_type">>, <<"client">>},
                              {<<"validator">>, false},
                              {<<"admin">>, false},
                              {<<"name">>, <<"">>}],
              ?assertEqual(lists:sort(ExpectedData), lists:sort(GotList))
      end
      }
    ].

osc_parse_binary_json_test_() ->
    [{"Can create with only URL name and has default values",
      fun() ->
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{}">>, <<"alice">>),
              ExpectedData = [{<<"json_class">>, <<"Chef::ApiClient">>},
                              {<<"chef_type">>, <<"client">>},
                              {<<"validator">>, false},
                              {<<"admin">>, false},
                              {<<"name">>, <<"alice">>}],
              {GotData} = Client,
              ?assertEqual(lists:sort(ExpectedData), lists:sort(GotData))
      end
     },

     {"Error thrown when missing both name and URL name",
      fun() ->
              Body = <<"{\"validator\":false}">>,
              ?assertThrow({both_missing, <<"name">>, <<"URL-NAME">>},
                           chef_client:osc_parse_binary_json(Body, undefined))
      end
     },

     {"Error thrown with bad name",
      fun() ->
              Body = <<"{\"name\":\"bad~name\"}">>,
              ?assertThrow({bad_client_name, <<"bad~name">>,
                            <<"Malformed client name.  Must be A-Z, a-z, 0-9, _, -, or .">>},
                           chef_client:osc_parse_binary_json(Body, <<"bad~name">>))
      end
     },
     {"Error thrown with both admin and validator set to true",
      fun() ->
              Body = <<"{\"name\":\"client\",\"admin\":true,\"validator\":true}">>,
              ?assertThrow(#ej_invalid{type = fun_match, msg = <<"Client can be either an admin or a validator, but not both.">>},
                           chef_client:osc_parse_binary_json(Body, <<"client">>))
      end
     },

     {"a null public_key is removed",
      fun() ->
              Body = chef_json:encode({[
                                        {<<"name">>, <<"client1">>},
                                        {<<"public_key">>, null}
                                       ]}),
              {ok, Got} = chef_client:osc_parse_binary_json(Body, <<"client1">>),
              ?assertEqual(undefined, ej:get({"public_key"}, Got))
      end},

     {"a valid public_key is preserved",
      fun() ->
              Body = chef_json:encode({[
                                        {<<"name">>, <<"client1">>},
                                        {<<"public_key">>, public_key_data()}
                                       ]}),
              {ok, Got} = chef_client:osc_parse_binary_json(Body, <<"client1">>),
              ?assertEqual(public_key_data(), ej:get({"public_key"}, Got))
      end},

     {"Errors thrown for invalid public_key data ", generator,
      fun() ->
              MungedKey = re:replace(public_key_data(), "A", "2",
                                     [{return, binary}, global]),
              BadKeys = [MungedKey,
                         <<"a very bad key">>,
                         true,
                         113,
                         [public_key_data()],
                         {[]}],
              Bodies = [ chef_json:encode({[
                                        {<<"name">>, <<"client1">>},
                                        {<<"public_key">>, Key}]})
                         || Key <- BadKeys ],
              [ ?_assertThrow(#ej_invalid{},
                              chef_client:osc_parse_binary_json(Body, <<"client1">>))
                || Body <- Bodies ]
      end},

     {"Inherits values from current admin client",
      fun() ->
              CurClient = #chef_client{admin = true, validator = false,
                                       public_key = public_key_data()},
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{}">>, <<"alice">>, CurClient),
              ExpectedData = [{<<"json_class">>, <<"Chef::ApiClient">>},
                              {<<"chef_type">>, <<"client">>},
                              {<<"validator">>, false},
                              {<<"admin">>, true},
                              {<<"public_key">>, public_key_data()},
                              {<<"name">>, <<"alice">>}],
              {GotData} = Client,
              ?assertEqual(lists:sort(ExpectedData), lists:sort(GotData))
      end
     },

     {"Inherits values from current validator client",
      fun() ->
              CurClient = #chef_client{admin = false, validator = true,
                                       public_key = public_key_data()},
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{}">>, <<"alice">>, CurClient),
              ExpectedData = [{<<"json_class">>, <<"Chef::ApiClient">>},
                              {<<"chef_type">>, <<"client">>},
                              {<<"validator">>, true},
                              {<<"admin">>, false},
                              {<<"public_key">>, public_key_data()},
                              {<<"name">>, <<"alice">>}],
              {GotData} = Client,
              ?assertEqual(lists:sort(ExpectedData), lists:sort(GotData))
      end
     },

     {"Inherits values from current admin client but can override true to false",
      fun() ->
              %% override true with false
              CurClient = #chef_client{admin = true, validator = false,
                                       public_key = public_key_data()},
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{\"validator\":false, \"admin\":false}">>,
                                                           <<"alice">>, CurClient),
              ?assertEqual(false, ej:get({"admin"}, Client)),
              ?assertEqual(false, ej:get({"validator"}, Client))
      end
     },

     {"Inherits values from current validator client but can override true to false",
      fun() ->
              %% override true with false
              CurClient = #chef_client{admin = false, validator = true,
                                       public_key = public_key_data()},
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{\"validator\":false, \"admin\":false}">>,
                                                           <<"alice">>, CurClient),
              ?assertEqual(false, ej:get({"validator"}, Client))
      end
     },

     {"Inherits values from current admin client but can override false to true",
       fun() ->
               %% override false with true
               CurClient = #chef_client{admin = true, validator = false,
                                        public_key = public_key_data()},
               {ok, Client} = chef_client:osc_parse_binary_json(<<"{\"validator\":true, \"admin\":false}">>,
                                                            <<"alice">>, CurClient),
               ?assertEqual(true, ej:get({"validator"}, Client))
       end
     },

     {"Inherits values from current validator client but can override false to true",
       fun() ->
               %% override false with true
               CurClient = #chef_client{admin = false, validator = true,
                                        public_key = public_key_data()},
               {ok, Client} = chef_client:osc_parse_binary_json(<<"{\"validator\":false, \"admin\":true}">>,
                                                            <<"alice">>, CurClient),
               ?assertEqual(true, ej:get({"admin"}, Client))
       end
     },

     {"Inherits a certificate",
      fun() ->
              %% override true with false
              CurClient = #chef_client{admin = true, validator = true,
                                       public_key = cert_data()},
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{\"validator\":false, \"admin\":false}">>,
                                                           <<"alice">>, CurClient),
              ?assertEqual(cert_data(), ej:get({"certificate"}, Client))
      end
     }

    ].


oc_parse_binary_json_test_() ->
    [{"Error thrown on mismatched names",
      fun() ->
          Body = <<"{\"name\":\"name\",\"clientname\":\"notname\"}">>,
          ?assertThrow({client_name_mismatch}, chef_client:oc_parse_binary_json(Body, <<"name">>))
      end
     },
     {"Can create with only name",
      fun() ->
          Body = <<"{\"name\":\"name\"}">>,
          {ok, Client} = chef_client:oc_parse_binary_json(Body, <<"name">>),
          Name = ej:get({<<"name">>}, Client),
          ClientName = ej:get({<<"clientname">>}, Client),
          ?assertEqual(Name, ClientName)
      end
     },
     {"Can create with only clientname",
      fun() ->
          Body = <<"{\"clientname\":\"name\"}">>,
          {ok, Client} = chef_client:oc_parse_binary_json(Body, <<"name">>),
          Name = ej:get({<<"name">>}, Client),
          ClientName = ej:get({<<"clientname">>}, Client),
          ?assertEqual(Name, ClientName)
      end
     },
     {"Error thrown with no name or clientname",
      fun() ->
          Body = <<"{\"validator\":false}">>,
          ?assertThrow({both_missing, <<"name">>, <<"clientname">>},
                       chef_client:oc_parse_binary_json(Body, undefined))
      end
     },
     {"Error thrown with bad name",
      fun() ->
          Body = <<"{\"name\":\"bad~name\"}">>,
          ?assertThrow({bad_client_name, <<"bad~name">>,
                        <<"Malformed client name.  Must be A-Z, a-z, 0-9, _, -, or .">>},
                       chef_client:oc_parse_binary_json(Body, <<"bad~name">>))
      end
     }
    ].
