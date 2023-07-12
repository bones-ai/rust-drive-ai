use array::ArrayTrait;
use cubit::types::vec2::{Vec2, Vec2Trait};
use cubit::types::fixed::{Fixed, FixedTrait, FixedPrint, ONE_u128};
use cubit::math::trig;

fn rotate(a: Vec2, sin_theta: Fixed, cos_theta: Fixed) -> Vec2 {
    let new_x = a.x * cos_theta - a.y * sin_theta;
    let new_y = a.x * sin_theta + a.y * cos_theta;
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


#[cfg(test)]
mod tests {
    use debug::PrintTrait;
    use cubit::types::vec2::{Vec2, Vec2Trait};
    use cubit::types::fixed::{Fixed, FixedTrait, FixedPrint};
    use cubit::test::helpers::assert_precise;
    use array::SpanTrait;

    use super::vertices;

    const TEN: felt252 = 184467440737095516160;
    const TWENTY: felt252 = 368934881474191032320;
    const FORTY: felt252 = 737869762948382064640;
    const DEG_30_IN_RADS: felt252 = 9658715196994321226;

    #[test]
    #[available_gas(20000000)]
    fn test_vertices() {
        let position = Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(TWENTY));
        let width = FixedTrait::from_felt(TEN);
        let height = FixedTrait::from_felt(TWENTY);
        let theta = FixedTrait::new(0_u128, false);

        let mut vertices = vertices(position, width, height, theta);

        assert_precise(*(vertices.at(0).x), TWENTY, 'invalid vertex_0', Option::None(()));
        assert_precise(*(vertices.at(0).y), FORTY, 'invalid vertex_0', Option::None(()));

        assert_precise(*(vertices.at(1).x), 0, 'invalid vertex_1', Option::None(()));
        assert_precise(*(vertices.at(1).y), FORTY, 'invalid vertex_1', Option::None(()));

        assert_precise(*(vertices.at(2).x), 0, 'invalid vertex_2', Option::None(()));
        assert_precise(*(vertices.at(2).y), 0, 'invalid vertex_2', Option::None(()));

        assert_precise(*(vertices.at(3).x), TWENTY, 'invalid vertex_3', Option::None(()));
        assert_precise(*(vertices.at(3).y), 0, 'invalid vertex_3', Option::None(()));

        let position = Vec2Trait::new(FixedTrait::from_felt(TEN), FixedTrait::from_felt(TWENTY));
        let width = FixedTrait::from_felt(TEN);
        let height = FixedTrait::from_felt(TWENTY);
        let theta = FixedTrait::from_felt(DEG_30_IN_RADS);

        vertices = vertices(position, width, height, theta);

        assert_precise(
            *(vertices.at(0).x), 159753090305067335160, 'invalid rotated vertex_0', Option::None(())
        );
        assert_precise(
            *(vertices.at(0).y), 780673828410437532220, 'invalid rotated vertex_0', Option::None(())
        );
        assert_precise(
            *(vertices.at(1).x),
            -159752327071118592360,
            'invalid rotated vertex_1',
            Option::None(())
        );
        assert_precise(
            *(vertices.at(1).y), 596206769290316387460, 'invalid rotated vertex_1', Option::None(())
        );
        assert_precise(
            *(vertices.at(2).x), 209181791169123697160, 'invalid rotated vertex_2', Option::None(())
        );
        assert_precise(
            *(vertices.at(2).y), -42804065462055467580, 'invalid rotated vertex_2', Option::None(())
        );
        assert_precise(
            *(vertices.at(3).x), 528687208545309624680, 'invalid rotated vertex_3', Option::None(())
        );
        assert_precise(
            *(vertices.at(3).y), 141662993658065677180, 'invalid rotated vertex_3', Option::None(())
        );
    }
}
