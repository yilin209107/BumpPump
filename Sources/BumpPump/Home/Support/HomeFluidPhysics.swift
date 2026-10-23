import Foundation
import CoreGraphics

struct HomeFluidVector {
  var x: Double = 0
  var y: Double = 0
  var length: Double { hypot(x, y) }
  var unit: Self { length > 0.0001 ? self * (1 / length) : .init(x: 1, y: 0) }
  static func + (a: Self, b: Self) -> Self { .init(x: a.x+b.x, y: a.y+b.y) }
  static func - (a: Self, b: Self) -> Self { .init(x: a.x-b.x, y: a.y-b.y) }
  static func * (a: Self, b: Double) -> Self { .init(x: a.x*b, y: a.y*b) }
  func dot(_ other: Self) -> Double { x*other.x + y*other.y }
}
struct HomeFluidBlob {
  var center: HomeFluidVector
  var velocity = HomeFluidVector()
  var radius: Double
  var radial = Array(repeating: 1.0, count: 24)
  var radialVelocity = Array(repeating: 0.0, count: 24)
  let phase: Double
  var points: [CGPoint] {
    radial.indices.map { index in
      let angle = Double(index) / Double(radial.count) * .pi * 2
      return CGPoint(x: center.x + cos(angle) * radius * radial[index], y: center.y + sin(angle) * radius * radial[index])
    }
  }
}
/// The moving colour anchors share one star-shaped envelope. The opaque base of
/// that envelope is coloured before compositing, so even its narrow necks stay joined.
enum HomeFluidSurface {
  static func outline(_ blobs: [HomeFluidBlob], samples: Int = 72, bounds: CGRect? = nil) -> [CGPoint] {
    guard !blobs.isEmpty else { return [] }
    let center = blobs.map(\.center).reduce(HomeFluidVector(), +) * (1 / Double(blobs.count))
    let core = blobs.map(\.radius).reduce(0, +) / Double(blobs.count) * 0.85
    var radii = (0..<samples).map { index -> Double in
      let angle = Double(index) / Double(samples) * .pi * 2
      let direction = HomeFluidVector(x: cos(angle), y: sin(angle))
      var extent = core
      for blob in blobs {
        let offset = blob.center-center
        let projection = offset.dot(direction)
        let node = Int(Double(index) / Double(samples) * Double(blob.radial.count)) % blob.radial.count
        let radius = blob.radius * blob.radial[node]
        let perpendicularSquared = max(0, offset.dot(offset)-projection*projection)
        if perpendicularSquared < radius*radius {
          extent = max(extent, projection + sqrt(radius*radius-perpendicularSquared))
        }
      }
      return extent
    }
    // Surface tension rounds the junctions into a continuous liquid silhouette.
    for _ in 0..<3 {
      let previous = radii
      for index in radii.indices { radii[index] = (previous[(index+samples-1)%samples] + previous[index]*2 + previous[(index+1)%samples])/4 }
    }
    return radii.enumerated().map { index, radius in
      let angle = Double(index)/Double(samples) * .pi*2
      let axis = HomeFluidVector(x: cos(angle), y: sin(angle))
      let confined = bounds.map { min(radius, rayLimit(center: center, axis: axis, bounds: $0)) } ?? radius
      return CGPoint(x: center.x + axis.x*confined, y: center.y + axis.y*confined)
    }
  }
  static func rayLimit(center: HomeFluidVector, axis: HomeFluidVector, bounds: CGRect) -> Double {
    var limit = Double.greatestFiniteMagnitude
    if axis.x > 0.00001 { limit = min(limit, (bounds.maxX-center.x)/axis.x) }
    if axis.x < -0.00001 { limit = min(limit, (bounds.minX-center.x)/axis.x) }
    if axis.y > 0.00001 { limit = min(limit, (bounds.maxY-center.y)/axis.y) }
    if axis.y < -0.00001 { limit = min(limit, (bounds.minY-center.y)/axis.y) }
    return max(0, limit)
  }
}
/// Small damped soft-body solver: center springs, contact pressure, tangential drag,
/// and a coupled ring of radial springs. No UI, random seeds, timers or global state.
struct HomeFluidPhysics {
  private(set) var blobs: [HomeFluidBlob] = []
  private(set) var contacts = 0
  private(set) var wallContacts = 0
  private(set) var boundary = CGRect.zero
  private var size = CGSize.zero
  private var time = 0.0
  mutating func advance(target: CGPoint, size newSize: CGSize, elapsed: Double, interactions: Bool = true, bounds: CGRect? = nil, walls: Bool = true) {
    guard newSize.width > 0, newSize.height > 0 else { return }
    let window = CGRect(origin: .zero, size: newSize)
    let requested = (bounds ?? window).intersection(window)
    boundary = requested.isNull || requested.width < 20 || requested.height < 20 ? window : requested
    let scale = Double(max(0.3, min(1.25, min(boundary.width, boundary.height) / 760)))
    let pointer = HomeFluidVector(x: min(boundary.maxX, max(boundary.minX, Double(target.x * newSize.width))), y: min(boundary.maxY, max(boundary.minY, Double(target.y * newSize.height))))
    if blobs.isEmpty {
      blobs = (0..<5).map { index in
        let phase = Double(index) * .pi * 2 / 5
        return HomeFluidBlob(center: pointer + .init(x: cos(phase)*72*scale, y: sin(phase)*58*scale), radius: [91, 77, 87, 72, 82][index] * scale, phase: phase)
      }
    } else if size != .zero && size != newSize {
      for index in blobs.indices {
        blobs[index].center.x *= Double(newSize.width / size.width)
        blobs[index].center.y *= Double(newSize.height / size.height)
        blobs[index].radius = [91, 77, 87, 72, 82][index] * scale
      }
    }
    size = newSize
    let dt = min(0.05, max(0.001, elapsed))
    let steps = max(1, Int(ceil(dt / (1.0/120))))
    for index in blobs.indices { blobs[index].radius = [91, 77, 87, 72, 82][index] * scale }
    for _ in 0..<steps { substep(target: pointer, dt: dt / Double(steps), scale: scale, interactions: interactions, walls: walls) }
  }
  private mutating func substep(target: HomeFluidVector, dt: Double, scale: Double, interactions: Bool, walls: Bool) {
    time += dt
    var acceleration = Array(repeating: HomeFluidVector(), count: blobs.count)
    var pressure = Array(repeating: Array(repeating: 0.0, count: 24), count: blobs.count)
    for index in blobs.indices {
      let phase = blobs[index].phase
      let rest = target + .init(x: cos(phase + sin(time*0.15)*0.12)*68*scale, y: sin(phase + sin(time*0.15)*0.12)*54*scale)
      acceleration[index] = (rest-blobs[index].center)*16 - blobs[index].velocity*7
    }
    contacts = 0
    wallContacts = 0
    if walls {
      for index in blobs.indices {
        let blob = blobs[index]
        let faces: [(HomeFluidVector, Double)] = [
          (.init(x: -1, y: 0), blob.center.x-boundary.minX),
          (.init(x: 1, y: 0), boundary.maxX-blob.center.x),
          (.init(x: 0, y: -1), blob.center.y-boundary.minY),
          (.init(x: 0, y: 1), boundary.maxY-blob.center.y)
        ]
        for (normal, distance) in faces {
          let overlap = max(0, blob.radius-distance)
          guard overlap > 0 else { continue }
          wallContacts += 1
          let fraction = min(0.75, overlap/blob.radius)
          let outgoing = max(0, blob.velocity.dot(normal))
          // A normal spring resists penetration; contact friction slows sliding.
          acceleration[index] = acceleration[index] - normal*(overlap*64 + outgoing*9)
          let tangent = HomeFluidVector(x: -normal.y, y: normal.x)
          acceleration[index] = acceleration[index] - tangent*(blob.velocity.dot(tangent)*fraction*3)
          for node in 0..<24 {
            let angle = Double(node)/24 * .pi*2
            let axis = HomeFluidVector(x: cos(angle), y: sin(angle))
            pressure[index][node] -= pow(max(0,axis.dot(normal)),2)*fraction*1.3
          }
        }
      }
    }
    if interactions {
      for first in blobs.indices {
        for second in blobs.indices where second > first {
          let delta = blobs[second].center - blobs[first].center
          let distance = max(1, delta.length)
          let normal = delta.unit
          let contactDistance = (blobs[first].radius + blobs[second].radius)*0.91
          let overlap = max(0, contactDistance-distance)
          guard overlap > 0 else { continue }
          contacts += 1
          let fraction = min(0.8, overlap / contactDistance)
          let tangent = HomeFluidVector(x: -normal.y, y: normal.x)
          let relativeVelocity = blobs[second].velocity-blobs[first].velocity
          // Contact pushes apart; tangential friction reduces relative sliding.
          let force = normal*(overlap*32)
          let drag = tangent*(relativeVelocity.dot(tangent)*fraction*4.5)
          acceleration[first] = acceleration[first]-force+drag
          acceleration[second] = acceleration[second]+force-drag
          for node in 0..<24 {
            let angle = Double(node)/24 * .pi*2
            let axis = HomeFluidVector(x: cos(angle), y: sin(angle))
            pressure[first][node] -= pow(max(0, axis.dot(normal)), 4)*fraction*0.82
            pressure[second][node] -= pow(max(0, -axis.dot(normal)), 4)*fraction*0.82
          }
        }
      }
    }
    for index in blobs.indices {
      blobs[index].velocity = blobs[index].velocity + acceleration[index]*dt
      let speed = blobs[index].velocity.length
      if speed > 1500*scale { blobs[index].velocity = blobs[index].velocity.unit*(1500*scale) }
      blobs[index].center = blobs[index].center + blobs[index].velocity*dt
      if walls {
        let inset = min(blobs[index].radius*0.56, min(boundary.width,boundary.height)*0.45)
        let minX = boundary.minX+inset, maxX = boundary.maxX-inset
        let minY = boundary.minY+inset, maxY = boundary.maxY-inset
        if blobs[index].center.x < minX { blobs[index].center.x = minX; blobs[index].velocity.x = max(0,-blobs[index].velocity.x*0.16) }
        if blobs[index].center.x > maxX { blobs[index].center.x = maxX; blobs[index].velocity.x = min(0,-blobs[index].velocity.x*0.16) }
        if blobs[index].center.y < minY { blobs[index].center.y = minY; blobs[index].velocity.y = max(0,-blobs[index].velocity.y*0.16) }
        if blobs[index].center.y > maxY { blobs[index].center.y = maxY; blobs[index].velocity.y = min(0,-blobs[index].velocity.y*0.16) }
      }
      let direction = blobs[index].velocity.unit
      let stretch = min(0.28, speed / max(1, 2100*scale))
      let compensation = -pressure[index].reduce(0, +)/24 * 0.65
      let previous = blobs[index].radial
      for node in 0..<24 {
        let angle = Double(node)/24 * .pi*2
        let axis = HomeFluidVector(x: cos(angle), y: sin(angle))
        let along = axis.dot(direction)
        let inertia = stretch*(2*along*along-1) - along*stretch*0.3
        let breathing = sin(time*0.8 + angle*3 + blobs[index].phase)*0.018
        let desired = max(0.58, min(1.4, 1 + pressure[index][node] + compensation + inertia + breathing))
        let neighbours = (previous[(node+23)%24] + previous[(node+1)%24])/2
        let radialAcceleration = (desired-previous[node])*40 + (neighbours-previous[node])*22 - blobs[index].radialVelocity[node]*9
        blobs[index].radialVelocity[node] += radialAcceleration*dt
        var radius = max(0.55, min(1.45, previous[node] + blobs[index].radialVelocity[node]*dt))
        if walls {
          let limit = HomeFluidSurface.rayLimit(center: blobs[index].center, axis: axis, bounds: boundary)/blobs[index].radius
          if radius > limit { radius = limit; blobs[index].radialVelocity[node] = min(0,blobs[index].radialVelocity[node]) }
        }
        blobs[index].radial[node] = radius
      }
    }
  }
}
