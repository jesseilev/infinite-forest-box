module Diagram exposing 
    ( checkAnimationFinished
    , hasSucceeded
    , initLevel1
    , initLevel2
    , initLevel3
    , initLevel4
    , Model 
    , Msg
    , subscriptions
    , update 
    , view 
    )

import Angle exposing (Angle)
import Array
import Axis2d exposing (Axis2d)
import Circle2d
import Direction2d exposing (Direction2d)
import Ease
import Float.Extra as Float
import Frame2d exposing (Frame2d)
import Geometry.Svg as Svg
import Html exposing (Html)
import Html.Events.Extra.Pointer as Pointer
import Length exposing (Length, Meters)
import LineSegment2d exposing (LineSegment2d)
import List.Extra as List
import Maybe.Extra as Maybe
import Pixels exposing (Pixels)
import Point2d exposing (Point2d)
import Polygon2d exposing (Polygon2d)
import Polyline2d exposing (Polyline2d)
import Quantity exposing (Quantity)
import Room exposing (Room)
import RoomItem exposing (RoomItem)
import Svg exposing (Svg)
import Svg.Attributes as Attr
import Rectangle2d exposing (Rectangle2d)
import Shared exposing (..)
import SightRay exposing (SightRay)
import Vector2d exposing (Vector2d)
import Time

-- MODEL --

type alias Model = 
    { room : Room
    , sightDirection : Direction
    , sightDistance : Length
    , mouseHoverArea : Maybe MouseHoverArea
    , mouseDragPos : Maybe Point
    , dragging : Bool
    , ticks : Int
    , photoAttempt : Maybe PhotoAttempt
    }

type MouseHoverArea
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
    init Room.level1
        (Direction2d.fromAngle (Angle.degrees 210))
        (Length.meters 3)

initLevel2 : Model 
initLevel2 = 
    init Room.level2 
        (Direction2d.fromAngle (Angle.degrees 130))
        (Length.meters 5)

initLevel3 : Model
initLevel3 =
    init Room.level3
        (Direction2d.fromAngle (Angle.degrees 80))
        (Length.meters 8.0)

initLevel4 : Model
initLevel4 =
    init Room.level4
        (Direction2d.fromAngle (Angle.degrees -133))
        (Length.meters 20.0)

init : Room -> Direction -> Length -> Model 
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

rayNormal : Model -> SightRay
rayNormal model =
    SightRay.fromRoomAndProjectedPath model.room
        (Shared.projectedSightline model.room.playerItem.pos 
            model.sightDirection 
            model.sightDistance
        )

projectedSightline : Model -> LineSegment
projectedSightline model = 
    Shared.projectedSightline model.room.playerItem.pos model.sightDirection model.sightDistance

hasSucceeded : Model -> Bool 
hasSucceeded model = 
    Maybe.isJust (successAnimation model)

-- UPDATE --

type Msg 
    = NoOp
    | MouseDragAt Point
    | DragStart
    | DragStop
    | MouseClickAt Point
    | MouseHoverOver (Maybe MouseHoverArea)
    | AdjustZoom Float
    | StepAnimation
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

        DragStop -> 
            { model 
                | dragging = False, mouseDragPos = Nothing 
                , photoAttempt = Just (nextPhotoAttempt model)
            }

        MouseHoverOver hover -> 
            { model | mouseHoverArea = hover }

        StepAnimation ->
            successAnimation model 
                |> Maybe.map (\ani -> 
                    { ani | step = ani.step + 1, transitionPct = Just 0.0 }
                )
                |> Maybe.map (\newAni -> 
                    if checkAnimationFinished model then
                        model
                    else 
                        model |> updateSuccessAnimation (\_ -> newAni)
                )
                |> Maybe.withDefault model

        Tick -> 
            successAnimation model
                |> Maybe.filter (\_ -> checkAnimationFinished model == False)
                |> Maybe.andThen .transitionPct 
                |> Maybe.map ((+) 0.02)
                |> Maybe.map (\newPct -> 
                    if newPct < 1.0 then
                        model |> updateSuccessAnimation (\ani -> 
                            { ani | transitionPct = Just newPct }
                        )
                    else 
                        model |> update StepAnimation
                )
                |> Maybe.withDefault model 
                |> (\newModel -> { newModel | ticks = model.ticks + 1 })

        _ ->
            model

checkAnimationFinished : Model -> Bool
checkAnimationFinished model = 
    successAnimation model 
        |> Maybe.map (\ani -> 
            ani.step >= List.length (SightRay.uncurledSeries (rayNormal model)) - 1
        )
        |> Maybe.withDefault False

updatePlayerDirection : Model -> Point -> Point -> Model
updatePlayerDirection model mousePos prevMousePos =
    let playerAngle = Direction2d.toAngle model.sightDirection in
    Shared.angleDiff model.room.playerItem.pos prevMousePos mousePos
        |> Maybe.map (Quantity.plus playerAngle)
        |> Maybe.withDefault playerAngle
        |> (\angle -> { model | sightDirection = Direction2d.fromAngle angle })

nextPhotoAttempt : Model -> PhotoAttempt 
nextPhotoAttempt model = 
    let 
        ray = 
            rayNormal model

        (_, itemHitM) = 
            case ray.end of 
                SightRay.TooFar p -> (p, Nothing)
                SightRay.EndAtItem p i -> (p, Just i)

        targetHit = 
            itemHitM == Just (Room.targetItem model.room)
                && closeEnough (SightRay.length ray) model.sightDistance
    in
    case (successAnimation model, targetHit, itemHitM) of 
        (Just alreadyExistingAni, _, _) -> 
            PhotoSuccess alreadyExistingAni
        (Nothing, False, Just item) ->
            PhotoFail (WrongItem item)
        (Nothing, _, Nothing) ->
            PhotoFail NoItem
        (Nothing, True, _) -> 
            PhotoSuccess (SuccessAnimation 0 (Just 0))
    
updateSuccessAnimation : (SuccessAnimation -> SuccessAnimation) -> Model -> Model
updateSuccessAnimation upd model = 
    case model.photoAttempt of 
        Just (PhotoSuccess ani) -> 
            { model | photoAttempt = Just (PhotoSuccess (upd ani)) }
        _ -> model

closeEnough : Length -> Length -> Bool
closeEnough =
    Quantity.equalWithin (RoomItem.radius |> Quantity.multiplyBy 2)


-- SUBSCRIPTIONS --

subscriptions : Model -> Sub Msg
subscriptions model = 
    let 
        animationM = successAnimation model

        animating = 
            animationM
                |> Maybe.map (\ani ->
                    Maybe.isJust ani.transitionPct 
                        && (checkAnimationFinished model == False)
                )
                |> Maybe.withDefault False
    in
    if animating || Maybe.isJust model.mouseHoverArea then
        Time.every 50 (\_ -> Tick)
    else 
        Sub.none

view : Model -> Html Msg
view model =
    Html.div 
        [ Pointer.onUp (\_ -> 
            if Maybe.isNothing (successAnimation model) then DragStop else NoOp )
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
            [ Attr.width (Shared.svgWidth |> String.fromFloat)
            , Attr.height (Shared.svgHeight |> String.fromFloat)
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
    let playerEmoji = if model.dragging then RoomItem.emojis.camera else RoomItem.emojis.cat in
    Svg.g 
        []
        [ Room.view (currentZoomScale model) (model.room |> Room.setPlayerEmoji playerEmoji)
        , viewBeam (successAnimation model) model
        , viewPhotoAttempt model
        , if model.mouseHoverArea == Just HoverBeam && not model.dragging then 
            SightRay.viewDistanceLabel (rayNormal model) 
          else 
            Shared.svgEmpty
        ]
        |> Svg.at (pixelsPerMeterWithZoomScale 1)
        |> Svg.relativeTo Shared.svgFrame

viewDiagramSuccess : Model -> SuccessAnimation -> Svg Msg
viewDiagramSuccess model animation = 
    let 
        initialRay = 
            rayNormal model

        realRoom = 
            model.room |> Room.setPlayerEmoji RoomItem.emojis.cameraFlash

        (currentRay, nextRayM) = 
            transitionRay animation (rayNormal model)

        reflectedRooms = 
            SightRay.hallway realRoom currentRay

        farthestRoom = 
            reflectedRooms |> List.last |> Maybe.withDefault realRoom

        nextRoomM = 
            currentRay
                |> SightRay.uncurl 
                |> Maybe.map (SightRay.hallway realRoom)
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
        [ reflectedRooms 
            |> List.drop 1 
            |> (\rs -> rs ++ (transitionRoomM |> Maybe.toList))
            |> List.map (Room.view (currentZoomScale model))
            |> Svg.g [ Attr.opacity "0.4" ]
        , Room.view (currentZoomScale model) realRoom
        , viewBeam (Just animation) model
        ]
        |> Svg.translateBy (Vector2d.from centroid Point2d.origin)
        |> Svg.at (pixelsPerMeterWithZoomScale (currentZoomScale model))
        |> Svg.relativeTo Shared.svgFrame

viewPhotoAttempt : Model -> Svg Msg
viewPhotoAttempt model = 
    case nextPhotoAttempt model of 
        PhotoSuccess animation ->
            rayPairForAnimation animation (rayNormal model)
                |> Tuple.first
                |> SightRay.endItem
                |> Maybe.map (\item -> 
                    Svg.circle2d 
                        [ Attr.stroke Shared.colors.yellow1
                        , Attr.strokeWidth "0.02"
                        , Attr.fill "none"
                        ]
                        (Circle2d.atPoint item.pos RoomItem.radius)
                )
                |> Maybe.withDefault Shared.svgEmpty
        _ -> Shared.svgEmpty


rayPairForAnimation : SuccessAnimation -> SightRay -> (SightRay, Maybe SightRay)
rayPairForAnimation animation ray = 
    ray 
        |> SightRay.uncurledSeries
        |> Array.fromList
        |> (\rs -> 
            ( Array.get animation.step rs |> Maybe.withDefault ray
            , Array.get (animation.step + 1) rs
            )
        )


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
            { angleLabels = if showAngles then SightRay.AllAngles else SightRay.NoAngles 
            , attributes = attrs
            , projectionAttributes = []
            , zoomScale = currentZoomScale model
            }

        draggableAttrs = 
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

        zoomScale = currentZoomScale model
    in 
    Svg.g []
        (List.concat
            [ SightRay.beam model.room (projectedSightline model) -- the yellow beam rays
                |> List.map transitionIfAnimating
                |> List.indexedMap (\i -> 
                    SightRay.viewWithOptions (options False 
                        [ Attr.stroke <| 
                            if model.dragging || model.mouseHoverArea == Just HoverBeam then 
                                Shared.colors.yellowDark 
                            else 
                                Shared.colors.yellowLight
                        , Attr.strokeDashoffset <| String.fromFloat 
                            (toFloat i + (toFloat (model.ticks) * 0.005))
                        , Attr.strokeDasharray <| String.fromFloat 
                            (i |> modBy 3 |> toFloat |> ((*) 0.03) |> ((+) 0.07))
                        , Attr.strokeWidth <| Shared.floatAttributeForZoom zoomScale 0.0075
                        ]
                    )
                )
            , [ ray -- the "true" ray, invisible but showing angles during mouse drag
                |> SightRay.viewWithOptions (options model.dragging [ Attr.opacity "0"]) 
              , ray -- a thick invisible line over the initial straight portion to detect the cursor
                |> SightRay.viewProjectionWithOptions
                    { angleLabels = SightRay.NoAngles 
                    , projectionAttributes = [] 
                    , attributes = draggableAttrs ++
                        [ Attr.opacity "0", Attr.strokeDasharray "0", Attr.strokeWidth "0.25"]
                    , zoomScale = currentZoomScale model 
                    }
              ]
            ]
        )

transitionRay : SuccessAnimation -> SightRay -> (SightRay, Maybe SightRay)
transitionRay animation curledRay = 
    rayPairForAnimation animation curledRay 
        |> (\(uncurledRay, nextUncurledRayM) -> 
            ( uncurledRay
            , Maybe.map2 (SightRay.interpolateFrom uncurledRay) 
                nextUncurledRayM 
                (animation.transitionPct |> Maybe.map pctForRay)
            )
        )

-- Frame, Units, Conversions --

pixelsPerMeterWithZoomScale : Float -> Quantity Float (Quantity.Rate Pixels Meters)
pixelsPerMeterWithZoomScale zoomScale = 
    Shared.pixelsPerMeter |> Quantity.multiplyBy zoomScale

mouseToSceneCoords : Float -> (Float, Float) -> Point
mouseToSceneCoords zoomScale (x, y) = 
    Point2d.pixels x y
        |> Point2d.placeIn Shared.svgFrame
        |> Point2d.at_ (pixelsPerMeterWithZoomScale zoomScale)



