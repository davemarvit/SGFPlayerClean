# Spinning Ball Fix - Technical Summary

**Date**: 2025-11-20
**Issue**: High CPU usage (spinning ball) in SGFPlayerClean app
**Status**: ✅ RESOLVED

## Problem

The app was experiencing high CPU usage, causing macOS to show the spinning ball cursor. The app appeared frozen even though no intensive computation was happening.

## Root Cause

**Infinite render loop** caused by reading `@Published` properties from `LayoutViewModel` directly in SwiftUI view body.

### The Loop

1. SwiftUI renders `ContentView2D.body`
2. Body reads `layoutVM.windowSize` (a `@Published` property)
3. Reading `@Published` property subscribes the view to changes
4. LayoutViewModel updates `windowSize`
5. View re-renders (goto step 1)

This creates an **infinite loop** where the view constantly re-renders itself.

## Diagnostic Process

Systematic testing isolated the issue:

| Test | Description | CPU Usage | Status |
|------|-------------|-----------|--------|
| Test 1 | Minimal view (no dependencies) | 0.1% | ✅ Pass |
| Test 2 | With AppModel | 0.6% | ✅ Pass |
| Test 3 | BoardViewModel without Combine | 0.0% | ✅ Pass |
| Test 4 | Full BoardViewModel with Combine | 0.1% | ✅ Pass |
| ContentView2D (broken) | Full UI with geometry | ~100% | ❌ Fail |
| ContentView2D (fixed) | Full UI with fix | 0.0% | ✅ Pass |

### Key Finding

The issue was **NOT** in:
- AppModel
- BoardViewModel
- Combine subscriptions
- SGFPlayer

The issue **WAS** in:
- ContentView2D reading `layoutVM.windowSize` in the view body

## Solution

### Fix Applied

**File**: `Views/ContentView2D.swift`

1. **Added local state** to cache window size:
```swift
@State private var windowSize: CGSize = .zero
```

2. **Use local state in body** instead of reading from LayoutViewModel:
```swift
// Before (infinite loop):
.frame(width: layoutVM.windowSize.width * 0.7)

// After (fixed):
.frame(width: windowSize.width * 0.7)
```

3. **Update both states in resize handler**:
```swift
private func handleWindowResize(_ newSize: CGSize) {
    guard newSize != windowSize else { return }

    // Update local state (used in body)
    windowSize = newSize

    // Update LayoutViewModel (for calculations)
    layoutVM.handleResize(
        newSize: newSize,
        boardSize: boardVM.boardSize,
        leftPanelWidth: newSize.width * 0.7
    )
}
```

4. **Use `.onChange` modifier** to detect size changes without creating a loop:
```swift
.onChange(of: geometry.size) { newSize in
    handleWindowResize(newSize)
}
```

## Results

- **CPU Usage**: 0.0% (idle state)
- **Memory**: 0.2% (normal)
- **UI**: Responsive and working
- **Performance**: No spinning ball

## Lessons Learned

### SwiftUI Best Practices

1. **Never read `@Published` properties directly in view body**
   - Use `@State` to cache values needed for layout
   - Update cached values in `.onChange` or other callbacks

2. **GeometryReader usage**
   - Always use `.onChange(of:)` to react to size changes
   - Never call setter methods directly in the body

3. **Preventing infinite loops**
   - Guard against redundant updates: `guard newSize != windowSize else { return }`
   - Separate "view state" from "business logic state"

## Files Modified

- ✅ `Views/ContentView2D.swift` - Added local windowSize state
- ✅ `SGFPlayerCleanApp.swift` - Restored to use ContentView2D
- ✅ `ViewModels/LayoutViewModel.swift` - Already had loop prevention

## Testing

All diagnostic tests pass:
- Minimal view: ✅
- With AppModel: ✅
- BoardViewModel (no Combine): ✅
- BoardViewModel (with Combine): ✅
- Full ContentView2D: ✅

## Next Steps

The spinning ball issue is completely resolved. The app is ready for:
- Phase 2: OGS integration
- Phase 3: Full UI features
- Phase 4: Advanced features

No further performance fixes needed.
