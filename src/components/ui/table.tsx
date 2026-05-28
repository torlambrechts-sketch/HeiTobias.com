import { type HTMLAttributes, type TdHTMLAttributes, type ThHTMLAttributes } from 'react'
import { cn } from '../../lib/cn.js'

export function Table({ className, ...props }: HTMLAttributes<HTMLTableElement>) {
  return <table className={cn('w-full border-collapse', className)} {...props} />
}

export function THead({ className, ...props }: HTMLAttributes<HTMLTableSectionElement>) {
  return <thead className={cn('text-left', className)} {...props} />
}

export function TBody({ className, ...props }: HTMLAttributes<HTMLTableSectionElement>) {
  return <tbody {...props} className={className} />
}

export function TR({ className, ...props }: HTMLAttributes<HTMLTableRowElement>) {
  return <tr className={cn('border-b border-hairline', className)} {...props} />
}

export function TH({ className, ...props }: ThHTMLAttributes<HTMLTableCellElement>) {
  return (
    <th
      className={cn('eyebrow py-3 pr-6 align-bottom border-b-2 border-ink', className)}
      {...props}
    />
  )
}

export function TD({ className, ...props }: TdHTMLAttributes<HTMLTableCellElement>) {
  return <td className={cn('py-4 pr-6 font-body text-sm align-top', className)} {...props} />
}
