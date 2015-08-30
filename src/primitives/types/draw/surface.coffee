Primitive = require '../../primitive'
Util      = require '../../../util'

class Surface extends Primitive
  @traits = ['node', 'object', 'visible', 'style', 'line', 'mesh', 'geometry', 'surface', 'position', 'grid', 'bind', 'shade']

  constructor: (node, context, helpers) ->
    super node, context, helpers

    @lineX = @lineY = @surface = null

  resize: () ->
    return unless @bind.points?

    dims = @bind.points.getActiveDimensions()
    {width, height, depth, items} = dims

    @surface.geometry.clip width, height, depth, items if @surface
    @lineX  .geometry.clip width, height, depth, items if @lineX
    @lineY  .geometry.clip height, width, depth, items if @lineY

  make: () ->
    # Bind to attached data sources
    @_helpers.bind.make [
      { to: 'geometry.points', trait: 'source' }
      { to: 'geometry.colors', trait: 'source' }
      { to: 'mesh.texture',    trait: 'source' }
    ]

    return unless @bind.points?

    # Build transform chain
    position = @_shaders.shader()

    # Fetch position and transform to view
    position = @bind.points.sourceShader position
    position = @_helpers.position.pipeline position

    # Prepare bound uniforms
    styleUniforms   = @_helpers.style.uniforms()
    wireUniforms    = @_helpers.style.uniforms()
    lineUniforms    = @_helpers.line.uniforms()
    surfaceUniforms = @_helpers.surface.uniforms()
    unitUniforms    = @_inherit('unit').getUnitUniforms()

    # Darken wireframe if needed for contrast
    # Auto z-bias wireframe over surface
    wireUniforms.styleColor  = @_attributes.make @_types.color()
    wireUniforms.styleZBias  = @_attributes.make @_types.number()
    @wireColor  = wireUniforms.styleColor.value
    @wireZBias  = wireUniforms.styleZBias
    @wireScratch = new THREE.Color

    # Fetch geometry dimensions
    dims   = @bind.points.getDimensions()
    {width, height, depth, items} = dims

    # Get display properties
    {shaded, fill, lineX, lineY, stroke, crossed} = @props

    objects = []

    # Build color lookup
    if @bind.colors
      color = @_shaders.shader()
      @bind.colors.sourceShader color

    # Build transition mask lookup
    mask = @_helpers.object.mask()

    # Build texture map lookup
    map = @bind.map?.sourceShader @_shaders.shader()

    # Build fragment material lookup
    material = @_helpers.shade.pipeline() || shaded

    # Make line and surface renderables
    {swizzle, swizzle2}  = @_helpers.position
    uniforms = Util.JS.merge unitUniforms, lineUniforms, styleUniforms, wireUniforms
    zUnits = if lineX or lineY then -50 else 0
    if lineX
      @lineX = @_renderables.make 'line',
                uniforms: uniforms
                samples:  width
                strips:   height
                ribbons:  depth
                layers:   items
                position: position
                color:    color
                zUnits:   -zUnits
                stroke:   stroke
                mask:     mask
      objects.push @lineX

    if lineY
      @lineY = @_renderables.make 'line',
                uniforms: uniforms
                samples:  height
                strips:   width
                ribbons:  depth
                layers:   items
                position: swizzle2 position, 'yxzw', 'yxzw'
                color:    swizzle  color,    'yxzw'
                zUnits:   -zUnits
                stroke:   stroke
                mask:     swizzle  mask,     if crossed then 'xyzw' else 'yxzw'
      objects.push @lineY

    if fill
      uniforms = Util.JS.merge unitUniforms, surfaceUniforms, styleUniforms
      @surface = @_renderables.make 'surface',
                uniforms: uniforms
                width:    width
                height:   height
                surfaces: depth
                layers:   items
                position: position
                color:    color
                material: shaded
                zUnits:   zUnits
                stroke:   stroke
                mask:     mask
      objects.push @surface

    @_helpers.visible.make()
    @_helpers.object.make objects

  made: () -> @resize()

  unmake: () ->
    @_helpers.bind.unmake()
    @_helpers.visible.unmake()
    @_helpers.object.unmake()

    @lineX = @lineY = @surface = null

  change: (changed, touched, init) ->
    return @rebuild() if changed['geometry.points'] or
                         changed['mesh.shaded'] or
                         changed['mesh.fill'] or
                         changed['line.stroke'] or
                         touched['grid']

    if changed['style.color'] or
       changed['mesh.fill'] or
       init

      fill   = @_get 'mesh.fill'
      color  = @_get 'style.color'

      @wireZBias.value = @_get('style.zBias') + 5
      @wireColor.copy color
      if fill
        c = @wireScratch
        c.setRGB color.x, color.y, color.z
        c
          .convertGammaToLinear()
          .multiplyScalar(.75)
          .convertLinearToGamma()
        @wireColor.x = c.r
        @wireColor.y = c.g
        @wireColor.z = c.b

module.exports = Surface