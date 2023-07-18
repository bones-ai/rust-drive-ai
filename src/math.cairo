use array::ArrayTrait;
use cubit::types::vec2::{Vec2, Vec2Trait};
use cubit::types::fixed::{Fixed, FixedTrait, FixedPrint};
use cubit::math::{trig, comp::{min, max}, core::{pow_int, sqrt}};

fn rotate(a: Vec2, sin_theta: Fixed, cos_theta: Fixed) -> Vec2 {
    // clockwise rotation is positive here
    let new_x = a.x * cos_theta + a.y * sin_theta;
    let new_y = -a.x * sin_theta + a.y * cos_theta;
    return Vec2Trait::new(new_x, new_y);
}

fn vertices(position: Vec2, width: Fixed, height: Fixed, theta: Fixed) -> Span<Vec2> {
    let mut vertices = ArrayTrait::<Vec2>::new();

    // To reduce sin and cos calculations
    let sin_theta = trig::sin_fast(theta);
    let cos_theta = trig::cos_fast(theta);

    let rel_vertex_0 = Vec2Trait::new(width, height); // relative to vehicle
    let rot_rel_vertex_0 = rotate(rel_vertex_0, sin_theta, cos_theta); // rotated rel to vehicle
    let vertex_0 = position + rot_rel_vertex_0; // relative to origin

    let rel_vertex_1 = Vec2Trait::new(-width, height);
    let rot_rel_vertex_1 = rotate(rel_vertex_1, sin_theta, cos_theta);
    let vertex_1 = position + rot_rel_vertex_1;

    // Get last two vertices by symmetry
    let vertex_2 = position - rot_rel_vertex_0;
    let vertex_3 = position - rot_rel_vertex_1;

    vertices.append(vertex_0);
    vertices.append(vertex_1);
    vertices.append(vertex_2);
    vertices.append(vertex_3);
    vertices.span()
}

// Cool algorithm - see pp. 4-10 at https://www.dcs.gla.ac.uk/~pat/52233/slides/Geometry1x1.pdf
// Determines if segments p1q1 and p2q2 intersect 
fn intersects(p1: Vec2, q1: Vec2, p2: Vec2, q2: Vec2) -> bool {
    let orientation_a = orientation(p1, q1, p2);
    let orientation_b = orientation(p1, q1, q2);

    // Either proof 1 or 2 proves intersection
    // Proof 1: two conditions must be met
    if orientation_a != orientation_b {
        return orientation(p2, q2, p1) != orientation(p2, q2, q1);
    }

    // Proof 2: three conditions must be met
    // All points are colinear, i.e. all orientations = 0
    if orientation_a != 1 || orientation_b != 1 {
        return false;
    }

    // x-projections overlap 
    if max(p1.x, q1.x) < min(p2.x, q2.x) { // x-projections do not overlap
        return false;
    } else if min(p1.x, q1.x) > max(p2.x, q2.x) { // x-projections do not overlap
        return false;
    // y-projections overlap
    } else if max(p1.y, q1.y) < min(p2.y, q2.y) { // y-projections do not overlap
        return false;
    } else if min(p1.y, q1.y) > max(p2.y, q2.y) { // y-projections do not overlap
        return false;
    }

    true
}

// Orientation = sign of cross product of vectors (b - a) and (c - b)
// (simpler than what they do in link above)
fn orientation(a: Vec2, b: Vec2, c: Vec2) -> u8 {
    let ab = b - a;
    let bc = c - b;
    let cross_product = ab.cross(bc);

    if cross_product.mag > 0 {
        if !cross_product.sign {
            return 2;
        }

        return 0;
    }

    return 1;
}

// Finds distance from p1 to intersection of segments p1q1 and p2q2
fn distance(p1: Vec2, p2: Vec2, q2: Vec2, cos_ray: Fixed, sin_ray: Fixed) -> Fixed {
    // All enemy edges are either vertical or horizontal
    if p2.y == q2.y { // Enemy edge is horizontal
        if p2.y == p1.y { // Ray is colinear with enemy edge
            return min((p2.x - p1.x).abs(), (q2.x - p1.x).abs());
        } else {
            return ((p2.y - p1.y) / cos_ray).abs();
        }
    } else { // Enemy edge is vertical
        if p2.x == p1.x { // Ray is colinear with enemy edge
            return min((p2.y - p1.y).abs(), (q2.y - p1.y).abs());
        } else {
            return ((p2.x - p1.x) / sin_ray).abs();
        }
    }
}

#[cfg(test)]
mod tests {
    use traits::Into;
    use debug::PrintTrait;
    use cubit::math::trig;
    use cubit::types::vec2::{Vec2, Vec2Trait};
    use cubit::types::fixed::{Fixed, FixedTrait, FixedPrint};
    use cubit::test::helpers::assert_precise;
    use array::SpanTrait;

    use super::{vertices, orientation, intersects, distance};

    const TEN: u128 = 184467440737095516160;
    const TWENTY: u128 = 368934881474191032320;
    const TWENTY_FIVE: u128 = 461168601842738790400;
    const THIRTY: u128 = 553402322211286548480;
    const FORTY: u128 = 737869762948382064640;
    const FIFTY: u128 = 922337203685477580800;
    const SIXTY: u128 = 1106804644422573096960;
    const EIGHTY: u128 = 1475739525896764129280;
    const HUNDRED: u128 = 1844674407370955161600;
    const DEG_30_IN_RADS: u128 = 9658715196994321226;
    const DEG_90_IN_RADS: u128 = 28976077338029890953;

    #[test]
    #[available_gas(20000000)]
    fn test_rotate() {
        let a = Vec2Trait::new(
            FixedTrait::new_unscaled(1_u128, false), FixedTrait::new_unscaled(2_u128, false)
        );
        let theta = FixedTrait::new(trig::HALF_PI_u128 / 3, false);
        let sin_theta = trig::sin_fast(theta);
        let cos_theta = trig::cos_fast(theta);

        let b = rotate(a, sin_theta, cos_theta);

        // x: ~-0.13397459621556135324, y: ~+2.2320508075688772935
        assert_precise(b.x, -2471395088767036514, 'invalid rotate x', Option::None(()));
        assert(b.x.sign == true, 'invalid rotate x');
        assert_precise(b.y, 41174070006739806010, 'invalid rotate y', Option::None(()));
        assert(b.y.sign == false, 'invalid rotate y');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_vertices() {
        let position = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(TWENTY, false));
        let width = FixedTrait::new(TEN, false);
        let height = FixedTrait::new(TWENTY, false);
        let theta = FixedTrait::new(0, false);

        let mut vertices = vertices(position, width, height, theta);

        assert_precise(*(vertices.at(0).x), TWENTY.into(), 'invalid vertex_0', Option::None(()));
        assert_precise(*(vertices.at(0).y), FORTY.into(), 'invalid vertex_0', Option::None(()));

        assert_precise(*(vertices.at(1).x), 0, 'invalid vertex_1', Option::None(()));
        assert_precise(*(vertices.at(1).y), FORTY.into(), 'invalid vertex_1', Option::None(()));

        assert_precise(*(vertices.at(2).x), 0, 'invalid vertex_2', Option::None(()));
        assert_precise(*(vertices.at(2).y), 0, 'invalid vertex_2', Option::None(()));

        assert_precise(*(vertices.at(3).x), TWENTY.into(), 'invalid vertex_3', Option::None(()));
        assert_precise(*(vertices.at(3).y), 0, 'invalid vertex_3', Option::None(()));

        let position = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(TWENTY, false));
        let width = FixedTrait::new(TEN, false);
        let height = FixedTrait::new(TWENTY, false);
        let theta = FixedTrait::new(DEG_30_IN_RADS, true);

        vertices = vertices(position, width, height, theta);

        // x: ~8.66025403784439, y: ~42.32050807568880
        assert_precise(
            *(vertices.at(0).x), 159753090305067335160, 'invalid rotated vertex_0', Option::None(())
        );
        assert_precise(
            *(vertices.at(0).y), 780673828410437532220, 'invalid rotated vertex_0', Option::None(())
        );

        // x: ~-8.66025403784439, y: ~32.32050807568880
        assert_precise(
            *(vertices.at(1).x),
            -159752327071118592360,
            'invalid rotated vertex_1',
            Option::None(())
        );
        assert_precise(
            *(vertices.at(1).y), 596206769290316387460, 'invalid rotated vertex_1', Option::None(())
        );

        // x: ~11.33974596215560, y: ~-2.32050807568877
        assert_precise(
            *(vertices.at(2).x), 209181791169123697160, 'invalid rotated vertex_2', Option::None(())
        );
        assert_precise(
            *(vertices.at(2).y), -42804065462055467580, 'invalid rotated vertex_2', Option::None(())
        );

        // x: ~28.66025403784440, y: ~7.67949192431123
        assert_precise(
            *(vertices.at(3).x), 528687208545309624680, 'invalid rotated vertex_3', Option::None(())
        );
        assert_precise(
            *(vertices.at(3).y), 141662993658065677180, 'invalid rotated vertex_3', Option::None(())
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_orientation() {
        let a = Vec2Trait::new(FixedTrait::new(0, false), FixedTrait::new(TEN, false));
        let b = Vec2Trait::new(FixedTrait::new(TWENTY, false), FixedTrait::new(TWENTY, false));
        let mut c = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(FORTY, false));
        let mut orientation = orientation(a, b, c);
        assert(orientation == 2_u8, 'invalid positive orientation');

        c = Vec2Trait::new(FixedTrait::new(FORTY, false), FixedTrait::new(THIRTY, false));
        orientation = orientation(a, b, c);
        assert(orientation == 1_u8, 'invalid zero orientation');

        c = Vec2Trait::new(FixedTrait::new(THIRTY, false), FixedTrait::zero());
        orientation = orientation(a, b, c);
        assert(orientation == 0_u8, 'invalid negative orientation');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_intersects() {
        // Four test for same lines, same intersection, but switching p's and q's for one or both lines
        let mut p1 = Vec2Trait::new(FixedTrait::new(FORTY, false), FixedTrait::new(THIRTY, false));
        let mut q1 = Vec2Trait::new(FixedTrait::new(0, false), FixedTrait::new(TEN, false));
        let mut p2 = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(FORTY, false));
        let mut q2 = Vec2Trait::new(FixedTrait::new(THIRTY, false), FixedTrait::new(0, false));
        let mut intersect = intersects(p1, q1, p2, q2);
        assert(intersect == true, 'invalid intersection');

        // Switch only p1,q1
        p1 = Vec2Trait::new(FixedTrait::new(0, false), FixedTrait::new(TEN, false));
        q1 = Vec2Trait::new(FixedTrait::new(FORTY, false), FixedTrait::new(THIRTY, false));
        p2 = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(FORTY, false));
        q2 = Vec2Trait::new(FixedTrait::new(THIRTY, false), FixedTrait::new(0, false));
        intersect = intersects(p1, q1, p2, q2);
        assert(intersect == true, 'invalid intersection');

        // Switch only p2,q2
        p1 = Vec2Trait::new(FixedTrait::new(FORTY, false), FixedTrait::new(THIRTY, false));
        q1 = Vec2Trait::new(FixedTrait::new(0, false), FixedTrait::new(TEN, false));
        p2 = Vec2Trait::new(FixedTrait::new(THIRTY, false), FixedTrait::new(0, false));
        q2 = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(FORTY, false));
        intersect = intersects(p1, q1, p2, q2);
        assert(intersect == true, 'invalid intersection');

        // Switch both p1,q1 and p2,q2
        p1 = Vec2Trait::new(FixedTrait::new(0, false), FixedTrait::new(TEN, false));
        q1 = Vec2Trait::new(FixedTrait::new(FORTY, false), FixedTrait::new(THIRTY, false));
        p2 = Vec2Trait::new(FixedTrait::new(THIRTY, false), FixedTrait::new(0, false));
        q2 = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(FORTY, false));
        intersect = intersects(p1, q1, p2, q2);
        assert(intersect == true, 'invalid intersection');

        // Now shorter line 2 so no intersection
        q2 = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(TEN, false));
        intersect = intersects(p1, q1, p2, q2);
        assert(intersect == false, 'invalid non-intersection');

        // Colinear segments
        q1 = Vec2Trait::new(FixedTrait::new(THIRTY, false), FixedTrait::new(TEN, false));
        p2 = Vec2Trait::new(FixedTrait::new(TWENTY, false), FixedTrait::new(TEN, false));
        q2 = Vec2Trait::new(FixedTrait::new(FORTY, false), FixedTrait::new(TEN, false));
        intersect = intersects(p1, q1, p2, q2);
        assert(intersect == true, 'invalid colinear intersection');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_distance() {
        let p1 = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(TWENTY, false));

        let ray_length = FixedTrait::new(FORTY, false);
        let mut ray = FixedTrait::new(DEG_30_IN_RADS, true);
        let mut cos_ray = trig::cos_fast(ray);
        let mut sin_ray = trig::sin_fast(ray);
        let mut delta1 = Vec2Trait::new(ray_length * sin_ray, ray_length * cos_ray);
        let mut q1 = p1 + delta1;
        let mut p2 = Vec2Trait::new(FixedTrait::new(TWENTY, false), FixedTrait::new(FIFTY, false));
        let mut q2 = Vec2Trait::new(FixedTrait::new(FORTY, false), FixedTrait::new(FIFTY, false));
        let mut dist = distance(p1, p2, q2, cos_ray, sin_ray);
        // ~34.6410161513775
        assert_precise(
            dist, 639017084058308293480, 'invalid distance horiz edge', Option::None(())
        );

        p2 = Vec2Trait::new(FixedTrait::new(TWENTY_FIVE, false), FixedTrait::new(FORTY, false));
        q2 = Vec2Trait::new(FixedTrait::new(TWENTY_FIVE, false), FixedTrait::new(SIXTY, false));
        dist = distance(p1, p2, q2, cos_ray, sin_ray);
        // ~23.0940107675850
        assert_precise(dist, 553403467064578077655, 'invalid distance vert edge', Option::None(()));

        ray = FixedTrait::new(DEG_90_IN_RADS, false);
        cos_ray = trig::cos_fast(ray);
        sin_ray = trig::sin_fast(ray);
        delta1 = Vec2Trait::new(ray_length * sin_ray, ray_length * cos_ray);
        q1 = p1 + delta1;
        p2 = Vec2Trait::new(FixedTrait::new(FORTY, false), FixedTrait::new(TWENTY, false));
        q2 = Vec2Trait::new(FixedTrait::new(SIXTY, false), FixedTrait::new(TWENTY, false));
        dist = distance(p1, p2, q2, cos_ray, sin_ray);
        // ~30.0
        assert_precise(
            dist, 553402322211287000000, 'invalid dist colin-horiz edge', Option::None(())
        );

        ray = FixedTrait::new(0, false);
        cos_ray = trig::cos_fast(ray);
        sin_ray = trig::sin_fast(ray);
        delta1 = Vec2Trait::new(ray_length * sin_ray, ray_length * cos_ray);
        q1 = p1 + delta1;
        p2 = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(FIFTY, false));
        q2 = Vec2Trait::new(FixedTrait::new(TEN, false), FixedTrait::new(EIGHTY, false));
        dist = distance(p1, p2, q2, cos_ray, sin_ray);
        // ~30.0
        assert_precise(
            dist, 553402322211287000000, 'invalid dist colin vert edge', Option::None(())
        );
    }
}
