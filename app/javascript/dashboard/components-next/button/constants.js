// `brand` is Lynomia's gradient treatment, opted into per call site. It is deliberately NOT the default
// for a primary button: the brand reaches every primary button through the `n-brand` token on the solid
// variant, and the gradient is for the rare promotional call to action that should stand apart from it.
export const VARIANT_OPTIONS = [
  'solid',
  'outline',
  'faded',
  'link',
  'ghost',
  'brand',
];
export const COLOR_OPTIONS = ['blue', 'ruby', 'amber', 'slate', 'teal'];
export const SIZE_OPTIONS = ['xs', 'sm', 'md', 'lg'];
export const JUSTIFY_OPTIONS = ['start', 'center', 'end'];

export const EXCLUDED_ATTRS = [
  'variant',
  'color',
  'size',
  'icon',
  'trailingIcon',
  'isLoading',
  ...VARIANT_OPTIONS,
  ...COLOR_OPTIONS,
  ...SIZE_OPTIONS,
  ...JUSTIFY_OPTIONS,
];
