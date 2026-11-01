import * as SelectPrimitive from "@radix-ui/react-select";
import { Check, ChevronDown } from "lucide-react";
import { forwardRef } from "react";
import type { ComponentPropsWithoutRef } from "react";
import { cn } from "@/lib/utils";

const Select = SelectPrimitive.Root;
const SelectValue = SelectPrimitive.Value;

/** Box, type size, focus ring and disabled state of a button that opens a list of field values. */
const FIELD_TRIGGER = cn(
  "flex h-9 items-center justify-between gap-2 rounded-lg border border-fd-border bg-fd-card px-3 py-1.5 text-base sm:text-sm",
  "focus:outline-none focus:ring-2 focus:ring-inset focus:ring-fd-ring",
  "disabled:cursor-not-allowed disabled:opacity-50",
);

const SelectTrigger = forwardRef<HTMLButtonElement, ComponentPropsWithoutRef<typeof SelectPrimitive.Trigger>>(
  ({ className, children, ...props }, ref) => (
    <SelectPrimitive.Trigger
      ref={ref}
      className={cn(FIELD_TRIGGER, "data-[placeholder]:text-fd-muted-foreground/50 [&>span]:truncate", className)}
      {...props}
    >
      {children}
      <SelectPrimitive.Icon asChild>
        <ChevronDown className="size-3.5 shrink-0 text-fd-muted-foreground" />
      </SelectPrimitive.Icon>
    </SelectPrimitive.Trigger>
  ),
);
SelectTrigger.displayName = "SelectTrigger";

const SelectContent = forwardRef<HTMLDivElement, ComponentPropsWithoutRef<typeof SelectPrimitive.Content>>(
  ({ className, children, position = "popper", ...props }, ref) => (
    <SelectPrimitive.Portal>
      <SelectPrimitive.Content
        ref={ref}
        className={cn(
          "relative z-50 max-h-72 overflow-hidden rounded-lg border border-fd-border bg-fd-popover py-1 shadow-md",
          "data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95",
          "data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95",
          position === "popper" && "w-[var(--radix-select-trigger-width)]",
          className,
        )}
        position={position}
        {...props}
      >
        <SelectPrimitive.Viewport
          className={cn(position === "popper" && "h-[var(--radix-select-content-available-height)]")}
        >
          {children}
        </SelectPrimitive.Viewport>
      </SelectPrimitive.Content>
    </SelectPrimitive.Portal>
  ),
);
SelectContent.displayName = "SelectContent";

const SelectItem = forwardRef<
  HTMLDivElement,
  ComponentPropsWithoutRef<typeof SelectPrimitive.Item> & { description?: string }
>(({ className, children, description, ...props }, ref) => (
  <SelectPrimitive.Item
    ref={ref}
    className={cn(
      "relative flex w-full cursor-default items-center py-1.5 pl-8 pr-3 text-base outline-none select-none sm:text-sm",
      "data-[highlighted]:bg-fd-accent data-[highlighted]:text-fd-accent-foreground",
      "data-[disabled]:pointer-events-none data-[disabled]:opacity-50",
      className,
    )}
    {...props}
  >
    <span className="absolute left-2 flex size-4 items-center justify-center">
      <SelectPrimitive.ItemIndicator>
        <Check className="size-3.5" />
      </SelectPrimitive.ItemIndicator>
    </span>
    <div>
      <SelectPrimitive.ItemText>{children}</SelectPrimitive.ItemText>
      {description && <div className="whitespace-pre-line text-xs text-fd-muted-foreground">{description}</div>}
    </div>
  </SelectPrimitive.Item>
));
SelectItem.displayName = "SelectItem";

export { FIELD_TRIGGER, Select, SelectContent, SelectItem, SelectTrigger, SelectValue };
