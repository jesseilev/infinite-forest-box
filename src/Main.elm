module Main exposing (..)

import Browser
import Color.Convert as Color
import Diagram 
import Element as El exposing (Element)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Element.Region as Region
import Html exposing (Html)
import List.Extra as List
import Quantity
import Shared


main = 
    Browser.element
        { init = init
        , update = update   
        , subscriptions = subscriptions
        , view = view
        }

type alias Model =
    { levelIndex : Int
    , levels : List Diagram.Model
    }

init : () -> (Model, Cmd Msg)
init _ =
    { levelIndex = 0
    , levels = 
        [ Diagram.initLevel1
        , Diagram.initLevel2
        , Diagram.initLevel3
        , Diagram.initLevel4 
        ]
    }
        |> Shared.noCmds

diagram : Model -> Diagram.Model
diagram model = 
    model.levels 
        |> List.getAt model.levelIndex
        |> Maybe.withDefault Diagram.initLevel1


-- SUBSCRIPTIONS -- 

subscriptions : Model -> Sub Msg
subscriptions model =
    diagram model |> Diagram.subscriptions |> Sub.map DiagramMsg


-- UPDATE --

type Msg 
    = NoOp
    | DiagramMsg Diagram.Msg
    | PreviousLevel 
    | NextLevel

update : Msg -> Model -> (Model, Cmd Msg)
update msg model = 
    case msg of 
        DiagramMsg dm -> 
            model 
                |> updateDiagramAtIndex model.levelIndex (Diagram.update dm)
                |> Shared.noCmds

        PreviousLevel ->
            { model | levelIndex = max 0 (model.levelIndex - 1) }
                |> updateDiagramAtIndex model.levelIndex Diagram.reset
                |> Shared.noCmds

        NextLevel -> 
            { model | levelIndex = min (List.length model.levels - 1) (model.levelIndex + 1) }
                |> updateDiagramAtIndex model.levelIndex Diagram.reset
                |> Shared.noCmds

        _ ->
            model 
                |> Shared.noCmds

updateDiagramAtIndex : Int -> (Diagram.Model -> Diagram.Model) -> Model -> Model 
updateDiagramAtIndex index upd model =
    { model | levels = model.levels 
        |> List.indexedMap (\i dia -> if i == index then upd dia else dia)
    }

-- VIEW --

view : Model -> Html Msg
view model = 
    El.layout 
        [ El.width (El.fill)
        , El.height El.fill 
        , El.centerX
        ]
        (El.el 
            [ El.width (El.fill |> El.maximum 700)
            , El.centerX 
            ] 
            (El.column 
                [ El.centerX 
                , El.paddingXY 20 20
                , El.spacing 30
                -- , El.width <| El.px 800
                , Font.size 16
                , Font.family 
                    [ Font.external
                        { name = "Cantarell"
                        , url = "https://fonts.googleapis.com/css?family=Cantarell"
                        }
                    ]
                , Font.color darkGrey
                ]
                [ El.el [ Region.heading 1, Font.size 30, El.paddingXY 0 20 ] 
                    <| El.text "Pat's Infinite Mirror Box"
                , El.el [ Region.heading 3, Font.size 22 ] <| El.text "Scenario"
                , El.paragraph paragraphAttrs 
                    [ El.text "Pat the Cat 🐈‍ is an avid wildlife photographer. "
                    , El.text "She recently bought a fancy new camera, "
                    , El.text "and is excited to start taking some pics, "
                    , El.text "especially to test out the range of its zoom capabilities."
                    ]
                , El.paragraph paragraphAttrs
                    [ El.text "Arriving home, Pat enters her "
                    , El.el [ ] (El.text "Infinite Mirror Box, ")
                    , El.text "a small room with 4 adjustable mirrors for walls. "
                    , El.text "The room doesn't contain much, just Garrett the Parrot 🦜 "
                    , El.text "and a few potted plants 🪴. "
                    , El.text "But the light bouncing around off the mirrored walls "
                    , El.text """gives Pat the illusion of standing in an "infinite forest" """
                    , El.text "surrounded by many plants and birds: "
                    , El.text " some close by, and others far away..."
                    ]
                , viewDiagramContainer model
                ]
            )
        )

viewDiagramContainer : Model -> Element Msg
viewDiagramContainer model = 
    El.column     
        [ El.centerX 
        , El.width El.fill
        , Border.width 2
        , Border.rounded 4
        , Border.color <| veryLightGrey
        ] 
        [ viewLevelControls model.levelIndex
        , El.column [ El.padding 10 ]  
            [ instructionsParagraph model.levelIndex (diagram model).sightDistance
            , El.el 
                [ El.centerX ] 
                ( diagram model 
                    |> Diagram.view 
                    |> El.html 
                    |> El.map DiagramMsg
                )
            ]
        ]

darkGrey = El.rgb 0.35 0.35 0.35 
lightGrey = El.rgb 0.7 0.7 0.7
veryLightGrey = El.rgb 0.9 0.9 0.9
yellow1 = El.rgb 0.85 0.65 0.4

viewLevelControls : Int -> Element Msg 
viewLevelControls levelIndex = 
    El.el 
        [ Region.heading 3
        , Font.size 20
        , Font.bold
        , El.centerX
        , El.paddingXY 15 15
        , El.width El.fill
        , Background.color veryLightGrey 
        , Font.color darkGrey
        ]
        <| El.row 
            [ El.spacing 20, El.centerX ] 
            [ Input.button [] { label = El.text "<", onPress = Just PreviousLevel }
            , levelIndex |> (+) 1 |> String.fromInt |> (++) "Level " |> El.text 
            , Input.button [] { label = El.text ">", onPress = Just NextLevel }
            ]

paragraphAttrs =
    [ El.spacing 15 ] 
        
instructionsParagraph levelIndex sightDistance = 
    El.paragraph 
        [ El.spacing 15
        -- , Font.size 15
        , El.paddingXY 40 40
        -- , Background.color lightGrey
        ]
        [ El.el [ ] 
            (El.text "Take a picture of a bird in the mirror that appears to be ")
        , El.el 
            [ Font.bold
            , Font.color yellow1
            ] 
            (El.text <| String.fromFloat (Quantity.unwrap sightDistance) ++ " meters away.")
        ]

