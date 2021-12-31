module Diagram exposing (..)

import Angle exposing (Angle)
import Arc2d
import Array
import Axis2d exposing (Axis2d)
import Browser
import Circle2d
import Color
import Convert
import Direction2d exposing (Direction2d)
import Element as El exposing (Element)
import Element.Background as Background
import Element.Border as Border
import Element.Events
import Element.Font as Font
import Element.Input as Input
import Element.Region as Region
import Float.Extra as Float
import Frame2d exposing (Frame2d)
import Geometry.Svg as Svg
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Events.Extra.Mouse as Mouse
import Html.Events.Extra.Pointer as Pointer
import Html.Events.Extra.Wheel as Wheel
import Length exposing (Length, Meters)
import LineSegment2d exposing (LineSegment2d)
import List.Extra as List
import List.Nonempty
import Maybe.Extra as Maybe
import Pixels exposing (Pixels, pixels)
import Point2d exposing (Point2d)
import Polygon2d exposing (Polygon2d)
import Polyline2d exposing (Polyline2d)
import Quantity exposing (Quantity)
import RayPath exposing (RayPath)
import Room exposing (Model)
import RoomItem exposing (RoomItem)
import Svg exposing (Svg)
import Svg.Attributes as Attr
import Convert exposing (lengthToPixels)
import Rectangle2d exposing (Rectangle2d)
import SketchPlane3d exposing (toPlane)
import TypedSvg
import TypedSvg.Attributes
import TypedSvg.Attributes.InPx
import TypedSvg.Types exposing (CoordinateSystem(..), Paint(..))
import Shared exposing (..)
import Sightray
import String exposing (startsWith)
import Vector2d exposing (Vector2d)
import Time
import Triangle2d
import Sightray exposing (Sightray)
import Circle2d exposing (centerPoint)
import TypedSvg.Types exposing (YesNo(..))
import TypedSvg.Attributes exposing (direction)
import Ease

-- MODEL --

type alias Model = 
    { room : Room.Model
    , sightDirection : Direction
    , sightDistance : Length
    , mouseHoverArea : Maybe HoverArea
    , mouseDragPos : Maybe Point
    , dragging : Bool
    , ticks : Int
    , photoAttempt : Maybe PhotoAttempt
    }

type HoverArea 
    = HoverRoom
    | HoverBeam

type PhotoAttempt
    = PhotoFail FailReason
    | PhotoSuccess SuccessAnimation

type FailReason
    = NoItem
    | WrongItem RoomItem
    | TooClose Length

type alias SuccessAnimation = 
    { step : Int 
    , transitionPct : Maybe Float
    }


initLevel1 : Model 
initLevel1 = 
    init Room.initLevel1
        (Direction2d.fromAngle (Angle.degrees 190))
        (Length.meters 3)

initLevel2 : Model 
initLevel2 = 
    init Room.initLevel2 
        (Direction2d.fromAngle (Angle.degrees 160))
        (Length.meters 5)

initLevel3 : Model
initLevel3 =
    init Room.initLevel3
        (Direction2d.fromAngle (Angle.degrees 105))
        (Length.meters 8.0)

initLevel4 : Model
initLevel4 =
    init Room.initLevel4
        (Direction2d.fromAngle (Angle.degrees -133))
        (Length.meters 20.0)

init : Room.Model -> Direction -> Length -> Model 
init room sightDir sightDist = 
    { room = room 
    , sightDirection = sightDir 
    , sightDistance = sightDist 
    , mouseHoverArea = Nothing
    , mouseDragPos = Nothing
    , dragging = False
    , ticks = 0
    , photoAttempt = Nothing
    }
    
reset : Model -> Model 
reset model = 
    { model 
        | mouseHoverArea = Nothing
        , mouseDragPos = Nothing
        , dragging = False
        , ticks = 0
        , photoAttempt = Nothing
    }


 -- MODEL PROPERTIES --

successAnimation : Model -> Maybe SuccessAnimation
successAnimation model = 
    case model.photoAttempt of 
        Just (PhotoSuccess ani) -> Just ani
        _ -> Nothing

currentZoomScale : Model -> Float
currentZoomScale model = 
    let 
        zoomScaleForStep s = toFloat (s + 1) ^ -0.8
        animation = successAnimation model
        step = animation |> Maybe.map .step |> Maybe.withDefault 0
        transitionPct = animation |> Maybe.andThen .transitionPct |> Maybe.withDefault 0 |> pctForRoom
    in
    Float.interpolateFrom (zoomScaleForStep step) 
        (zoomScaleForStep (step + 1))
        (transitionPct) 

rayNormal : Model -> Sightray
rayNormal model =
    Sightray.fromRoomAndProjectedPath model.room
        (Shared.projectedSightline model.room.playerItem.pos 
            model.sightDirection 
            model.sightDistance
        )


rayDistance model =
    rayNormal model 
        |> Sightray.length
        |> (\dist -> 
            if closeEnough model.sightDistance dist then model.sightDistance else dist
        )
        |> Length.inMeters
        |> ((*) 100)
        |> round
        |> toFloat 
        |> (\l -> l / 100)


-- UPDATE --

type Msg 
    = NoOp
    | MouseDragAt Point
    | DragStart
    | DragStop
    | MouseClickAt Point
    | MouseHoverOver (Maybe HoverArea)
    | AdjustZoom Float
    | StepAnimation Int
    | Tick

update : Msg -> Model -> Model
update msg model = 
    case msg of 
        MouseDragAt mousePosInScene ->
            if not model.dragging then 
                model
            else 
                model.mouseDragPos 
                    |> Maybe.map (updatePlayerDirection model mousePosInScene)
                    |> Maybe.withDefault model
                    |> (\updModel -> 
                        { updModel | mouseDragPos = Just mousePosInScene, dragging = True }
                    )

        DragStart -> 
            { model | dragging = True, mouseDragPos = Nothing }
                -- |> updateRoomStatus

        DragStop -> 
            { model | dragging = False, mouseDragPos = Nothing }
                |> updatePhotoAttempt
                -- |> updateRoomStatus

        MouseClickAt sceneOffsetPos -> 
            model 
                |> (if Maybe.isNothing (successAnimation model) then updatePhotoAttempt else identity)

        MouseHoverOver hover -> 
            { model | mouseHoverArea = hover }

        StepAnimation stepDiff ->
            model |> updateSuccessAnimation (\ani -> 
                { ani | transitionPct = Just 0.0 }
            )

        Tick -> 
            { model | ticks = model.ticks + 1 }
                |> updateSuccessAnimation (\ani -> 
                    case ani.transitionPct of 
                        Nothing -> ani
                        Just pct -> pct + 0.02 |> (\newPct -> 
                            if newPct < 1.0 then 
                                { ani | transitionPct = Just newPct }
                            else 
                                { ani | step = ani.step + 1, transitionPct = Just 0 }
                            )
                )

        _ ->
            model


updatePlayerDirection : Model -> Point -> Point -> Model
updatePlayerDirection model mousePos prevMousePos =
    let playerAngle = Direction2d.toAngle model.sightDirection in
    Shared.angleDiff model.room.playerItem.pos prevMousePos mousePos
        |> Maybe.map (Quantity.plus playerAngle)
        |> Maybe.withDefault playerAngle
        |> (\angle -> { model | sightDirection = Direction2d.fromAngle angle })

updatePhotoAttempt : Model -> Model 
updatePhotoAttempt model = 
    let 
        ray = 
            rayNormal model

        sightEnd = 
            ray |> Sightray.endPos 

        itemHit = 
            Room.allItems model.room
                |> List.filter (RoomItem.containsPoint sightEnd)
                |> List.head -- TODO handle more than one? shouldnt be possible

        targetHit = 
            Sightray.endItem ray == Just (Room.targetItem model.room)
                && closeEnough (Sightray.length ray) model.sightDistance

        newPhotoAttempt = 
            case (model.photoAttempt, targetHit) of 
                (Nothing, True) -> 
                    Just <| PhotoSuccess (SuccessAnimation 0 (Just 0))
                -- (Nothing, Just False) ->
                --     Just <| PhotoFail (WrongItem itemHit)
                -- (Nothing, Nothing) ->
                --     Just <| PhotoFail (NoItem)
                --     -- TODO handle other fail types
                _ ->
                    model.photoAttempt
    in
    { model | photoAttempt = newPhotoAttempt }
    
updateSuccessAnimation : (SuccessAnimation -> SuccessAnimation) -> Model -> Model
updateSuccessAnimation upd model = 
    case model.photoAttempt of 
        Just (PhotoSuccess ani) -> { model | photoAttempt = Just (PhotoSuccess (upd ani)) }
        _ -> model

closeEnough : Length -> Length -> Bool
closeEnough =
    Quantity.equalWithin (RoomItem.radius |> Quantity.multiplyBy 2)

-- roomStatus model = 
--     case ((successAnimation model), model.dragging) of
--         (Just _, _) -> Room.TakingPic
--         (_, False) -> Room.Standing
--         (_, True) -> Room.LookingAround

-- updateRoomStatus model =
--     { model | room = Room.update (Room.setStatusMsg <| roomStatus model) model.room }


-- SUBSCRIPTIONS --

subscriptions : Model -> Sub Msg
subscriptions model = 
    if 
        Maybe.isJust model.mouseHoverArea 
            || Maybe.isJust (successAnimation model |> Maybe.andThen .transitionPct)
    then
        Time.every 50 (\_ -> Tick)
    else 
        Sub.none
    -- successAnimation model
    --     |> Maybe.andThen .transitionPct
    --     |> Maybe.map (\_ -> Time.every 50 (\_ -> Tick))
    --     |> Maybe.withDefault Sub.none


-- VIEW --

view : Model -> Html Msg
view model =
    Html.div 
        [ Pointer.onUp (\_ -> 
            if Maybe.isJust (successAnimation model) then StepAnimation 1 else DragStop)
        , Pointer.onLeave (\_ -> DragStop)
        , Pointer.onMove (\event -> 
            if model.dragging then 
                MouseDragAt (mouseToSceneCoords (currentZoomScale model) event.pointer.offsetPos)
            else 
                NoOp)
        , Pointer.onEnter (\_ -> MouseHoverOver (Just HoverRoom))
        , Pointer.onLeave (\_ -> MouseHoverOver Nothing)
        ]
        [ Svg.svg 
            [ Attr.width (Shared.constants.containerWidth |> String.fromFloat)
            , Attr.height (Shared.constants.containerHeight |> String.fromFloat)
            ]
            [ Svg.g 
                []
                [ (successAnimation model) 
                    |> Maybe.map (viewDiagramSuccess model)
                    |> Maybe.withDefault (viewDiagramNormal model)
                ]
            ]
        ]

viewDiagramNormal : Model -> Svg Msg
viewDiagramNormal model =
    Svg.g 
        []
        [ Room.view (currentZoomScale model) model.room
        , viewBeam (successAnimation model) model
        ]
        |> Svg.at (pixelsPerMeterWithZoomScale 1)
        |> Svg.relativeTo Shared.svgFrame


rayPairForAnimation : SuccessAnimation -> Sightray -> (Sightray, Maybe Sightray)
rayPairForAnimation animation ray = 
    ray 
        |> Sightray.uncurledSeries
        |> Array.fromList
        |> (\rs -> 
            ( Array.get animation.step rs |> Maybe.withDefault ray
            , Array.get (animation.step + 1) rs
            )
        )

viewDiagramSuccess : Model -> SuccessAnimation -> Svg Msg
viewDiagramSuccess model animation = 
    let 
        initialRay = 
            rayNormal model

        (currentRay, nextRayM) = 
            transitionRay animation (rayNormal model)

        reflectedRooms = 
            currentRay |> Sightray.hallway model.room 

        farthestRoom = 
            reflectedRooms |> List.last |> Maybe.withDefault model.room

        nextRoomM = 
            currentRay
                |> Sightray.uncurl 
                |> Maybe.map (Sightray.hallway model.room)
                |> Maybe.andThen List.last

        transitionRoomM = 
            Maybe.map2 (Room.interpolateFrom farthestRoom)
                nextRoomM
                (animation.transitionPct |> Maybe.map pctForRoom)

        centroid = 
            reflectedRooms ++ (transitionRoomM |> Maybe.toList)
                |> List.map (.wallShape >> Polygon2d.vertices)
                |> List.concat
                |> Polygon2d.convexHull
                |> Polygon2d.centroid
                |> Maybe.withDefault initialRay.startPos
    in
    Svg.g [ ] 
        [ reflectedRooms ++ (transitionRoomM |> Maybe.toList)
            |> List.map (Room.view (currentZoomScale model))
            |> Svg.g [ Attr.opacity "0.4" ]
        , Room.view (currentZoomScale model) model.room
        , viewBeam (Just animation) model
        ]
        |> Svg.translateBy (Vector2d.from centroid Point2d.origin)
        |> Svg.at (pixelsPerMeterWithZoomScale (currentZoomScale model))
        |> Svg.relativeTo Shared.svgFrame

pctForRoom = 
    clamp 0 0.5 >> (\n -> n * 2) >> Ease.inOutCubic

pctForRay = 
    clamp 0.5 1 >> (\x -> (x * 2) - 1) >> Ease.inOutCubic

viewBeam : Maybe SuccessAnimation -> Model -> Svg Msg 
viewBeam animationM model = 
    let 
        ray = 
            rayNormal model

        options showAngles attrs = 
            { angleLabels = if showAngles then Sightray.AllAngles else Sightray.NoAngles 
            , attributes = attrs
            , projectionAttributes = []
            , zoomScale = currentZoomScale model
            }

        gAttrs = 
            if Maybe.isNothing animationM then 
                [ Attr.cursor (if model.dragging then "grabbing" else "grab") 
                , Pointer.onDown (\_ -> if Maybe.isNothing animationM then DragStart else NoOp)
                , Pointer.onEnter (\_ -> MouseHoverOver (Just HoverBeam))
                , Pointer.onLeave (\_ -> MouseHoverOver (Just HoverRoom))
                ]
            else
                []

        transitionIfAnimating beamRay = 
            animationM 
                |> Maybe.map (\ani -> transitionRay ani beamRay)
                |> Maybe.map (\(r, rM) -> Maybe.withDefault r rM)
                |> Maybe.withDefault beamRay

    in 
    Svg.g gAttrs
        (List.concat
            [ [ ray -- draw a thick invisible ray behind the others to detect the cursor consistently 
                |> Sightray.viewWithOptions (options False 
                    [ Attr.opacity "0", Attr.strokeDasharray "0", Attr.strokeWidth "0.25"]
                )
              ]
            , Sightray.beam model.room (projectedSightline model) -- the yellow beam rays
                |> List.map transitionIfAnimating
                |> List.indexedMap (\i -> 
                    Sightray.viewWithOptions (options False 
                        [ Attr.stroke <| 
                            if model.dragging || model.mouseHoverArea == Just HoverBeam then 
                                Shared.colors.yellowDark 
                            else 
                                Shared.colors.yellowLight
                        , Attr.strokeDashoffset <| Shared.floatAttribute 1 
                            (toFloat i + (toFloat (model.ticks) * 0.005))
                        , Attr.strokeDasharray <| Shared.floatAttribute 1 
                            (i |> modBy 3 |> toFloat |> ((*) 0.03) |> ((+) 0.07))
                        , Attr.strokeWidth <| Shared.floatAttribute (currentZoomScale model) 0.0075
                        ]
                    )
                )
            , [ ray -- the "true" ray, invisible but showing angles during mouse drag
                |> Sightray.viewWithOptions (options model.dragging [ Attr.opacity "0"]) 
              ]
            ]
        )

transitionRay : SuccessAnimation -> Sightray -> (Sightray, Maybe Sightray)
transitionRay animation curledRay = 
    rayPairForAnimation animation curledRay 
        |> (\(uncurledRay, nextUncurledRayM) -> 
            ( uncurledRay
            , Maybe.map2 (Sightray.interpolateFrom uncurledRay) 
                nextUncurledRayM 
                (animation.transitionPct |> Maybe.map pctForRay)
            )
        )

projectedSightline model = 
    Shared.projectedSightline model.room.playerItem.pos model.sightDirection model.sightDistance

rayEndpointLabel ray = 
    let 
        itemM = 
            Sightray.endItem ray
        center = 
            itemM |> Maybe.map .pos |> Maybe.withDefault (Sightray.endPos ray)
            
    in
    Svg.g [] 
        [ Svg.circle2d 
            [ Attr.fill <| if Maybe.isJust itemM then "none" else "white"
            , Attr.strokeWidth "0.01"
            , Attr.stroke "black"
            ]
            (Circle2d.atPoint center RoomItem.radius)
        , Svg.text_ 
            [ Attr.fontSize "0.125" --(String.fromFloat "fontSize")
            , Attr.x (-0.5 * 0.25 |> String.fromFloat)
            , Attr.fill "black"
            , Attr.alignmentBaseline "central"
            ] 
            [ "8m"
                |> Svg.text 
            ]
            |> Svg.mirrorAcross (Axis2d.through Point2d.origin Direction2d.x)
            |> Svg.translateBy (Vector2d.from Point2d.origin center)
        ]

-- Frame, Units, Conversions --

pixelsPerMeterWithZoomScale : Float -> Quantity Float (Quantity.Rate Pixels Meters)
pixelsPerMeterWithZoomScale zoomScale = 
    Shared.pixelsPerMeter |> Quantity.multiplyBy zoomScale

mouseToSceneCoords : Float -> (Float, Float) -> Point2d Meters SceneCoords
mouseToSceneCoords zoomScale (x, y) = 
    Point2d.pixels x y
        |> Point2d.placeIn Shared.svgFrame
        |> Point2d.at_ (pixelsPerMeterWithZoomScale zoomScale)

svgToSceneCoords : Frame2d Pixels globalC { defines : localC } -> Svg msg -> Svg msg
svgToSceneCoords localFrame svg =
    svg 
        |> Svg.mirrorAcross Axis2d.x 
        |> Svg.placeIn localFrame

