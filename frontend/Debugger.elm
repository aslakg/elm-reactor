module Debugger where

import Html exposing (..)
import Html.Attributes as Attr exposing (..)
import Html.Events exposing (..)
import Signal
import Task exposing (Task)
import Json.Decode as JsDec
import String
import Color
import Debug

import Components exposing (..)
import Empty exposing (..)
import WebSocket

import Model exposing (..)
import Styles exposing (..)
import Button
import Debugger.RuntimeApi as API
import Debugger.Service as Service
import SideBar.Controls as Controls
import SideBar.Logs as Logs
import DataUtils exposing (..)


output =
  start
    { init =
        request (task connectSocket) initModel
    , view = view
    , update = update
    }


main =
  output.html


port tasks : Signal (Task Never ())
port tasks =
  output.tasks


(=>) = (,)


view : Signal.Address Message -> Model -> Html
view addr state =
  let
    (mainVal, isPlaying) =
      case state.serviceState of
        Just activeAttrs ->
          (activeAttrs.mainVal, DM.isPlaying activeAttrs)

        Nothing ->
          (div [] [], False)

  in
    div []
      [ mainVal
      , eventBlocker (not isPlaying)
      , viewSidebar addr state
      ]


eventBlocker : Bool -> Html
eventBlocker visible =
  div
    [ id "elm-reactor-event-blocker"
    , style
        [ "position" => "absolute"
        , "top" => "0"
        , "left" => "0"
        , "width" => "100%"
        , "height" => "100%"
        , "display" => if visible then "block" else "none"
        ]
    ]
    []


tabWidth = 25

toggleTab : Signal.Address Action -> Model -> Html
toggleTab addr state =
  div
    [ style
        [ "position" => "absolute"
        , "width" => intToPx tabWidth
        , "height" => "60px"
        , "top" => "50%"
        , "left" => intToPx -tabWidth
        , "border-top-left-radius" => "3px"
        , "border-bottom-left-radius" => "3px"
        , "background" => colorToCss darkGrey
        ]
    , onClick addr (SidebarVisible <| not state.sidebarVisible)
    ]
    []


viewSidebar : Signal.Address Action -> Model -> Html
viewSidebar addr state =
  let
    constantStyles =
      [ "background-color" => colorToCss darkGrey
      , "width" => intToPx sidebarWidth
      , "position" => "absolute"
      , "top" => "0"
      , "bottom" => "0"
      , "transition-duration" => "0.3s"
      , "opacity" => "0.97"
      , "z-index" => "1"
      ]
    
    toggleStyles =
      if state.sidebarVisible then
        [ "right" => "0" ]
      else
        [ "right" => intToPx -sidebarWidth ]

    dividerBar =
      div
        [ style
            [ "height" => "1px"
            , "width" => intToPx sidebarWidth
            , "opacity" => "0.3"
            , "background-color" => colorToCss Color.lightGrey
            ]
        ]
        []

    body =
      case state.serviceState of
        DM.Active activeAttrs ->
          [ Controls.view
              addr
              state
              activeAttrs
          , dividerBar
          , Logs.view
              (Signal.forwardTo addr LogsAction)
              Controls.totalHeight
              state.logsState
              activeAttrs
          ]

        _ ->
          -- TODO: prettify
          [ div
              [style [ "color" => "white" ]]
              [text "Initialzing..."]
          ]
  in
    div
      [ id "elm-reactor-side-bar"
      -- done in JS: cancelBubble / stopPropagation on this
      , style (constantStyles ++ toggleStyles)
      ]
      ([toggleTab addr state] ++ body)


update : Message -> Model -> Transaction Message Model
update msg model =
  case msg of
    _ ->
      done model

{-
update : FancyStartApp.UpdateFun Model Empty Action
update loopback now action state =
  case Debug.log "MAIN ACTION" action of
    SidebarVisible visible ->
      ( { state | sidebarVisible <- visible }
      , []
      )

    PermitSwaps permitSwaps ->
      ( { state | permitSwaps <- permitSwaps }
      , []
      )

    NewServiceState serviceState ->
        ( { state
              | serviceState <- serviceState
              , logsState <-
                  Logs.update (Logs.UpdateLogs serviceState) state.logsState
          }
        , []
        )

    PlayPauseButtonAction action ->
      ( { state | playPauseButtonState <-
            Button.update action state.playPauseButtonState
        }
      , []
      )

    RestartButtonAction action ->
      ( { state | restartButtonState <-
            Button.update action state.restartButtonState
        }
      , []
      )

    LogsAction action ->
      ( { state | logsState <- Logs.update action state.logsState }
      , []
      )

    ConnectSocket maybeSocket ->
      ( { state | swapSocket <- maybeSocket }
      , []
      )

    SwapEvent swapEvent ->
      case swapEvent of
        NewModule compiledModule ->
          let
            mod =
              API.evalModule compiledModule
          in
            ( state
            , [ Signal.send (Service.commandsMailbox ()).address (DM.Swap mod) ]
            )

        CompilationErrors errors ->
          Debug.crash errors
-}

-- Socket stuff

socketEventsMailbox : Signal.Mailbox Action
socketEventsMailbox =
  Signal.mailbox NoOp

-- INPUT PORT: initial module

port initMod : API.ElmModule

port fileName : String

-- would be nice to get this from a library
port windowLocationHost : String

-- TASK PORTS

-- TODO: external events in Elm Components so we can add this in
connectSocket : Task Never Message
connectSocket =
  (WebSocket.create
    ("ws://" ++ windowLocationHost ++ "/socket?file=" ++ fileName)
    (Signal.forwardTo
      socketEventsMailbox.address
      (\evt ->
        case evt of
          WebSocket.Message msg ->
            msg
              |> JsDec.decodeString swapEvent
              |> getResult
              |> SwapEvent

          WebSocket.Close ->
            ConnectSocket Nothing
      )
    )
  )
  |> Task.map (ConnectSocket << Just)


port uiTasksPort : Signal (Task Empty ())
port uiTasksPort =
  uiTasks


--port debugServiceTasks : Signal (Task Empty ())
--port debugServiceTasks =
--  Service.tasks
