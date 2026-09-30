# Forward seamless pagination and South post menus

## Changes

The old reader required at least 56 points of bottom overscroll while the finger
was still interacting with the scroll view. An ordinary forward drag or flick
that reached the end after release could never satisfy that condition.

Forward pagination now starts within 200 points of the content end while moving
forward in a user gesture or that gesture's deceleration. Each gesture can
request at most one adjacent page. Idle layout changes, programmatic scrolling,
backward motion, and a short page's top bounce cannot trigger a next-page load.
Top pagination keeps its deliberate 56-point pull requirement.

The phase callback samples current geometry when releasing the finger and when
reaching idle, so a late final geometry sample is not lost. Insets are included
when calculating the end. A retained, unpublished observation object prevents
per-pixel geometry changes from invalidating the whole post list.

The next-page loading/error indicator is in a reserved content footer. It does
not overlap the bottom toolbar. Existing window joins preserve post identities
and visible anchors. Loaded page one and page two remain joined; the next
request comes from the window's last page.
Forward responses append immediately during a drag or flick when no content
above the viewport needs eviction; prepend/eviction waits for a settled anchor.

South post menus use a 24 x 18 point rounded rectangle with a 6 point continuous
corner radius and 10 point ellipsis. The 44 x 44 point transparent hit area is
retained for accessibility and reliable taps.

## Validation

Regression coverage includes forward drags without overscroll, flicks crossing
the threshold after release, first/last pages, short-page top bounce, no duplicate
loads per gesture, toolbar insets, and South page 1/2/3 joins after prepending.
Physical-device gesture acceptance remains necessary; no simulator is used.

Apple's API separates interacting and decelerating phases and supplies geometry
at phase transitions:

- https://developer.apple.com/documentation/swiftui/scrollphase
- https://developer.apple.com/documentation/swiftui/view/onscrollphasechange(_:)-1k12m
- https://developer.apple.com/documentation/swiftui/scrollgeometry
