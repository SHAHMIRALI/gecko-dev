/* -*- Mode: Objective-C++; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#import "mozActionElements.h"

#import "MacUtils.h"
#include "Accessible-inl.h"
#include "DocAccessible.h"
#include "XULTabAccessible.h"

#include "nsDeckFrame.h"
#include "nsObjCExceptions.h"

using namespace mozilla::a11y;

enum CheckboxValue {
  // these constants correspond to the values in the OS
  kUnchecked = 0,
  kChecked = 1,
  kMixed = 2
};

@implementation mozButtonAccessible

- (NSArray*)accessibilityAttributeNames {
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_NIL;

  static NSArray* attributes = nil;
  if (!attributes) {
    attributes = [[NSArray alloc]
        initWithObjects:NSAccessibilityParentAttribute,  // required
                        NSAccessibilityRoleAttribute,    // required
                        NSAccessibilityRoleDescriptionAttribute,
                        NSAccessibilityPositionAttribute,           // required
                        NSAccessibilitySizeAttribute,               // required
                        NSAccessibilityWindowAttribute,             // required
                        NSAccessibilityPositionAttribute,           // required
                        NSAccessibilityTopLevelUIElementAttribute,  // required
                        NSAccessibilityHelpAttribute,
                        NSAccessibilityEnabledAttribute,  // required
                        NSAccessibilityFocusedAttribute,  // required
                        NSAccessibilityTitleAttribute,    // required
                        NSAccessibilityChildrenAttribute, NSAccessibilityDescriptionAttribute,
#if DEBUG
                        @"AXMozDescription",
#endif
                        nil];
  }
  return attributes;

  NS_OBJC_END_TRY_ABORT_BLOCK_NIL;
}

- (id)accessibilityAttributeValue:(NSString*)attribute {
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_NIL;

  if ([attribute isEqualToString:NSAccessibilityChildrenAttribute]) {
    if ([self hasPopup]) return [self children];
    return nil;
  }

  return [super accessibilityAttributeValue:attribute];

  NS_OBJC_END_TRY_ABORT_BLOCK_NIL;
}

- (BOOL)accessibilityIsIgnored {
  return ![self getGeckoAccessible] && ![self getProxyAccessible];
}

- (NSArray*)accessibilityActionNames {
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_NIL;

  NSArray* actions = [super accessibilityActionNames];
  if ([self isEnabled]) {
    // VoiceOver expects the press action to be the first in the list.
    if ([self hasPopup]) {
      return [@[ NSAccessibilityPressAction, NSAccessibilityShowMenuAction ]
          arrayByAddingObjectsFromArray:actions];
    }
    return [@[ NSAccessibilityPressAction ] arrayByAddingObjectsFromArray:actions];
  }

  return actions;

  NS_OBJC_END_TRY_ABORT_BLOCK_NIL;
}

- (NSString*)accessibilityActionDescription:(NSString*)action {
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_NIL;

  if ([action isEqualToString:NSAccessibilityPressAction]) {
    return @"press button";  // XXX: localize this later?
  }

  if ([self hasPopup]) {
    if ([action isEqualToString:NSAccessibilityShowMenuAction]) return @"show menu";
  }

  return nil;

  NS_OBJC_END_TRY_ABORT_BLOCK_NIL;
}

- (void)accessibilityPerformAction:(NSString*)action {
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK;

  if ([self isEnabled] && [action isEqualToString:NSAccessibilityPressAction]) {
    // TODO: this should bring up the menu, but currently doesn't.
    //       once msaa and atk have merged better, they will implement
    //       the action needed to show the menu.
    [self click];
  } else {
    [super accessibilityPerformAction:action];
  }

  NS_OBJC_END_TRY_ABORT_BLOCK;
}

- (void)click {
  // both buttons and checkboxes have only one action. we should really stop using arbitrary
  // arrays with actions, and define constants for these actions.
  if (AccessibleWrap* accWrap = [self getGeckoAccessible]) {
    accWrap->DoAction(0);
  } else if (ProxyAccessible* proxy = [self getProxyAccessible]) {
    proxy->DoAction(0);
  }
}

- (BOOL)hasPopup {
  if (AccessibleWrap* accWrap = [self getGeckoAccessible])
    return accWrap->NativeState() & states::HASPOPUP;

  if (ProxyAccessible* proxy = [self getProxyAccessible])
    return proxy->NativeState() & states::HASPOPUP;

  return false;
}

@end

@implementation mozCheckboxAccessible

- (NSString*)accessibilityActionDescription:(NSString*)action {
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_NIL;

  if ([action isEqualToString:NSAccessibilityPressAction]) {
    if ([self isChecked] != kUnchecked) return @"uncheck checkbox";  // XXX: localize this later?

    return @"check checkbox";  // XXX: localize this later?
  }

  return nil;

  NS_OBJC_END_TRY_ABORT_BLOCK_NIL;
}

- (int)isChecked {
  // check if we're checked or in a mixed state
  if ([self state] & states::CHECKED) {
    return ([self state] & states::MIXED) ? kMixed : kChecked;
  }

  return kUnchecked;
}

- (id)value {
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_NIL;

  return [NSNumber numberWithInt:[self isChecked]];

  NS_OBJC_END_TRY_ABORT_BLOCK_NIL;
}

@end

@implementation mozPaneAccessible

- (NSUInteger)accessibilityArrayAttributeCount:(NSString*)attribute {
  AccessibleWrap* accWrap = [self getGeckoAccessible];
  ProxyAccessible* proxy = [self getProxyAccessible];
  if (!accWrap && !proxy) return 0;

  // By default this calls -[[mozAccessible children] count].
  // Since we don't cache mChildren. This is faster.
  if ([attribute isEqualToString:NSAccessibilityChildrenAttribute]) {
    if (accWrap) return accWrap->ChildCount() ? 1 : 0;

    return proxy->ChildrenCount() ? 1 : 0;
  }

  return [super accessibilityArrayAttributeCount:attribute];
}

- (NSArray*)children {
  if (![self getGeckoAccessible]) return nil;

  nsDeckFrame* deckFrame = do_QueryFrame([self getGeckoAccessible]->GetFrame());
  nsIFrame* selectedFrame = deckFrame ? deckFrame->GetSelectedBox() : nullptr;

  Accessible* selectedAcc = nullptr;
  if (selectedFrame) {
    nsINode* node = selectedFrame->GetContent();
    selectedAcc = [self getGeckoAccessible]->Document() -> GetAccessible(node);
  }

  if (selectedAcc) {
    mozAccessible* curNative = GetNativeFromGeckoAccessible(selectedAcc);
    if (curNative) return [NSArray arrayWithObjects:GetObjectOrRepresentedView(curNative), nil];
  }

  return nil;
}

@end
