/*
* Box2D.XNA port of Box2D:
* Copyright (c) 2009 Brandon Furtwangler, Nathan Furtwangler
*
* Original source Box2D:
* Copyright (c) 2006-2009 Erin Catto http://www.gphysics.com
*
* This software is provided 'as-is', without any express or implied
* warranty.  In no event will the authors be held liable for any damages
* arising from the use of this software.
* Permission is granted to anyone to use this software for any purpose,
* including commercial applications, and to alter it and redistribute it
* freely, subject to the following restrictions:
* 1. The origin of this software must not be misrepresented; you must not
* claim that you wrote the original software. If you use this software
* in a product, an acknowledgment in the product documentation would be
* appreciated but is not required.
* 2. Altered source versions must be plainly marked as such, and must not be
* misrepresented as being the original software.
* 3. This notice may not be removed or altered from any source distribution.
*/

using Uno.Collections;

namespace Uno.Physics.Box2D
{
    /// A contact edge is used to connect bodies and contacts together
    /// in a contact graph where each body is a box2dNode and each contact
    /// is an edge. A contact edge belongs to a doubly linked list
    /// maintained in each attached body. Each contact has two contact
    /// box2dNodes, one for each attached body.
    public class ContactEdge
    {
        public Body Other;			///< provides quick access to the other body attached.
        public Contact Contact;		///< the contact
        public ContactEdge Prev;	///< the previous contact edge in the body's contact list
        public ContactEdge Next;	///< the next contact edge in the body's contact list
    }

    [Flags]
    public enum ContactFlags
    {
        None = 0,

        // Used when crawling contact graph when forming islands.
        Island = 0x0001,

        // Set when the shapes are touching.
        Touching = 0x0002,

        // This contact can be disabled (by user)
        Enabled = 0x0004,

        // This contact needs filtering because a fixture filter was changed.
        Filter = 0x0008,

        // This bullet contact had a TOI event
        BulletHit = 0x0010,
    }

    /// The class manages contact between two shapes. A contact exists for each overlapping
    /// AABB in the broad-phase (except if filtered). Therefore a contact object may exist
    /// that has no contact points.
    public class Contact
    {
        /// Get the contact manifold. Do not modify the manifold unless you understand the
        /// internals of Box2D.
	    public void GetManifold(out Manifold manifold)
        {
            manifold = _manifold;
        }

	    /// Get the world manifold.
	    public void GetWorldManifold(out WorldManifold worldManifold)
        {
            Body bodyA = _fixtureA.GetBody();
	        Body bodyB = _fixtureB.GetBody();
	        Shape shapeA = _fixtureA.GetShape();
	        Shape shapeB = _fixtureB.GetShape();

            Transform xfA, xfB;
            bodyA.GetTransform(out xfA);
            bodyB.GetTransform(out xfB);

            worldManifold = new WorldManifold(ref _manifold, ref xfA, shapeA._radius, ref xfB, shapeB._radius);
        }

        /// Is this contact touching?
	    public bool IsTouching()
        {
            return (_flags & ContactFlags.Touching) == ContactFlags.Touching;
        }

        /// Enable/disable this contact. This can be used inside the pre-solve
	    /// contact listener. The contact is only disabled for the current
	    /// time step (or sub-step in continuous collisions).
        public void SetEnabled(bool flag)
        {
            if (flag)
            {
                _flags |= ContactFlags.Enabled;
            }
            else
            {
                _flags &= ~ContactFlags.Enabled;
            }
        }

        /// Has this contact been disabled?
        public bool IsEnabled()
        {
            return (_flags & ContactFlags.Enabled) == ContactFlags.Enabled;
        }

	    /// Get the next contact in the world's contact list.
	    public Contact GetNext()
        {
            return _next;
        }

        /// Get fixture A in this contact.
	    public Fixture GetFixtureA()
        {
            return _fixtureA;
        }

	    /// Get fixture B in this contact.
	    public Fixture GetFixtureB()
        {
            return _fixtureB;
        }

        /// Get the child primitive index for fixture A.
        public int GetChildIndexA()
        {
            return _indexA;
        }

        /// Get the child primitive index for fixture B.
        public int GetChildIndexB()
        {
            return _indexB;
        }

	    /// Flag this contact for filtering. Filtering will occur the next time step.
	    public void FlagForFiltering()
        {
            _flags |= ContactFlags.Filter;
        }

        internal Contact(Fixture fA, int indexA, Fixture fB, int indexB)
        {
            Reset(fA, indexA, fB, indexB);
        }

        internal void Reset(Fixture fA, int indexA, Fixture fB, int indexB)
        {
            _flags = ContactFlags.Enabled;

	        _fixtureA = fA;
	        _fixtureB = fB;

            _indexA = indexA;
            _indexB = indexB;

	        _manifold._pointCount = 0;

	        _prev = null;
	        _next = null;

	        _box2dNodeA.Contact = null;
	        _box2dNodeA.Prev = null;
	        _box2dNodeA.Next = null;
	        _box2dNodeA.Other = null;

	        _box2dNodeB.Contact = null;
	        _box2dNodeB.Prev = null;
	        _box2dNodeB.Next = null;
	        _box2dNodeB.Other = null;

            _toiCount = 0;
        }

        // Update the contact manifold and touching status.
        // Note: do not assume the fixture AABBs are overlapping or are valid.
	    internal void Update(IContactListener listener)
        {
            Manifold oldManifold = _manifold;

            // Re-enable this contact.
            _flags |= ContactFlags.Enabled;

            bool touching = false;
            bool wasTouching = (_flags & ContactFlags.Touching) == ContactFlags.Touching;

            bool sensorA = _fixtureA.IsSensor();
            bool sensorB = _fixtureB.IsSensor();
            bool sensor = sensorA || sensorB;

	        Body bodyA = _fixtureA.GetBody();
	        Body bodyB = _fixtureB.GetBody();
	        Transform xfA; bodyA.GetTransform(out xfA);
	        Transform xfB; bodyB.GetTransform(out xfB);

	        // Is this contact a sensor?
	        if (sensor)
	        {
		        Shape shapeA = _fixtureA.GetShape();
		        Shape shapeB = _fixtureB.GetShape();
		        touching = AABB.TestOverlap(shapeA, _indexA, shapeB, _indexB, ref xfA, ref xfB);

		        // Sensors don't generate manifolds.
		        _manifold._pointCount = 0;
	        }
	        else
	        {
		        Evaluate(ref _manifold, ref xfA, ref xfB);
		        touching = _manifold._pointCount > 0;

		        // Match old contact ids to new contact ids and copy the
		        // stored impulses to warm start the solver.
		        for (int i = 0; i < _manifold._pointCount; ++i)
		        {
			        ManifoldPoint mp2 = _manifold._points[i];
			        mp2.NormalImpulse = 0.0f;
			        mp2.TangentImpulse = 0.0f;
			        ContactID id2 = mp2.Id;
                    bool found = false;

			        for (int j = 0; j < oldManifold._pointCount; ++j)
			        {
				        ManifoldPoint mp1 = oldManifold._points[j];

				        if (mp1.Id.Key == id2.Key)
				        {
					        mp2.NormalImpulse = mp1.NormalImpulse;
					        mp2.TangentImpulse = mp1.TangentImpulse;
                            found = true;
					        break;
				        }
			        }
                    if (found == false)
                    {
                        mp2.NormalImpulse = 0.0f;
                        mp2.TangentImpulse = 0.0f;
                    }

                    _manifold._points[i] = mp2;
		        }

		        if (touching != wasTouching)
		        {
			        bodyA.SetAwake(true);
			        bodyB.SetAwake(true);
		        }
	        }

	        if (touching)
	        {
		        _flags |= ContactFlags.Touching;
	        }
	        else
	        {
		        _flags &= ~ContactFlags.Touching;
	        }

	        if (wasTouching == false && touching == true && null != listener)
	        {
		        listener.BeginContact(this);
	        }

	        if (wasTouching == true && touching == false && null != listener)
	        {
		        listener.EndContact(this);
	        }

	        if (sensor == false && null != listener)
	        {
		        listener.PreSolve(this, ref oldManifold);
	        }
        }

        private static EdgeShape s_edge = new EdgeShape();

        /// Evaluate this contact with your own manifold and transforms.
        internal void Evaluate(ref Manifold manifold, ref Transform xfA, ref Transform xfB)
        {
            switch (_type)
            {
                case ContactType.Polygon:
                    Collision.CollidePolygons(ref manifold,
                            (PolygonShape)_fixtureA.GetShape(), ref xfA,
                            (PolygonShape)_fixtureB.GetShape(), ref xfB);
                    break;
                case ContactType.PolygonAndCircle:
                    Collision.CollidePolygonAndCircle(ref manifold,
                            (PolygonShape)_fixtureA.GetShape(), ref xfA,
                            (CircleShape) _fixtureB.GetShape(), ref xfB);
                    break;
                case ContactType.EdgeAndCircle:
                    Collision.CollideEdgeAndCircle(ref manifold,
                            (EdgeShape)  _fixtureA.GetShape(), ref xfA,
                            (CircleShape)_fixtureB.GetShape(), ref xfB);
                    break;
                case ContactType.EdgeAndPolygon:
                    Collision.CollideEdgeAndPolygon(ref manifold,
                            (EdgeShape)   _fixtureA.GetShape(), ref xfA,
                            (PolygonShape)_fixtureB.GetShape(), ref xfB);
                    break;
                case ContactType.LoopAndCircle:
                    var loop = (LoopShape)_fixtureA.GetShape();
                    loop.GetChildEdge(ref s_edge, _indexA);
                    Collision.CollideEdgeAndCircle(ref manifold, s_edge, ref xfA,
                            (CircleShape)_fixtureB.GetShape(), ref xfB);
                    break;
                case ContactType.LoopAndPolygon:
                    var loop2 = (LoopShape)_fixtureA.GetShape();
                    loop2.GetChildEdge(ref s_edge, _indexA);
                    Collision.CollideEdgeAndPolygon(ref manifold, s_edge, ref xfA,
                            (PolygonShape)_fixtureB.GetShape(), ref xfB);
                    break;
                case ContactType.Circle:
                    Collision.CollideCircles(ref manifold,
                            (CircleShape)_fixtureA.GetShape(), ref xfA,
                            (CircleShape)_fixtureB.GetShape(), ref xfB);
                    break;
            }
        }

        internal enum ContactType
        {
            Polygon,
            PolygonAndCircle,
            Circle,
            EdgeAndPolygon,
            EdgeAndCircle,
            LoopAndPolygon,
            LoopAndCircle,
        }

        /*public enum ShapeType
        {
            Unknown = -1,
            Circle = 0,
            Edge = 1,
            Polygon = 2,
            Loop = 3,
            TypeCount = 4,
        };*/

        internal static ContactType[][] s_registers = new ContactType[][]
        {
            new [] {
              ContactType.Circle,
              ContactType.EdgeAndCircle,
              ContactType.PolygonAndCircle,
              ContactType.LoopAndCircle,
            },
            new [] {
              ContactType.EdgeAndCircle,
              ContactType.EdgeAndCircle,  // 1,1 is invalid (no ContactType.Edge)
              ContactType.EdgeAndPolygon,
              ContactType.EdgeAndPolygon, // 1,3 is invalid (no ContactType.EdgeAndLoop)
            },
            new [] {
              ContactType.PolygonAndCircle,
              ContactType.EdgeAndPolygon,
              ContactType.Polygon,
              ContactType.LoopAndPolygon,
            },
            new [] {
              ContactType.LoopAndCircle,
              ContactType.LoopAndCircle,  // 3,1 is invalid (no ContactType.EdgeAndLoop)
              ContactType.LoopAndPolygon,
              ContactType.LoopAndPolygon, // 3,3 is invalid (no ContactType.Loop)
            },
        };

        internal static Contact Create(Fixture fixtureA, int indexA, Fixture fixtureB, int indexB)
        {
            ShapeType type1 = fixtureA.ShapeType;
	        ShapeType type2 = fixtureB.ShapeType;




            Contact c;
            var pool = fixtureA._body._world._contactPool;
            if (pool.Count > 0)
            {
                c = pool.Dequeue();
                if (((int)type1 >= (int)type2 || (type1 == ShapeType.Edge && type2 == ShapeType.Polygon))
                    &&
                    !(type2 == ShapeType.Edge && type1 == ShapeType.Polygon))
                {
                    c.Reset(fixtureA, indexA, fixtureB, indexB);
                }
                else
                {
                    c.Reset(fixtureB, indexB, fixtureA, indexA);
                }
            }
            else
            {
                // Edge+Polygon is non-symetrical due to the way Erin handles collision type registration.
                if (((int)type1 >= (int)type2 || (type1 == ShapeType.Edge && type2 == ShapeType.Polygon))
                    &&
                    !(type2 == ShapeType.Edge && type1 == ShapeType.Polygon))
                {
                    c = new Contact(fixtureA, indexA, fixtureB, indexB);
                }
                else
                {
                    c = new Contact(fixtureB, indexB, fixtureA, indexA);
                }
            }

            c._type = Contact.s_registers[(int)type1][(int)type2];

            return c;
        }

        internal void Destroy()
        {
            _fixtureA._body._world._contactPool.Enqueue(this);
            Reset(null, 0, null, 0);
        }

        private ContactType _type;
	    internal ContactFlags _flags;

	    // World pool and list pointers.
	    internal Contact _prev;
	    internal Contact _next;

	    // Nodes for connecting bodies.
	    internal ContactEdge _box2dNodeA = new ContactEdge();
        internal ContactEdge _box2dNodeB = new ContactEdge();

	    internal Fixture _fixtureA;
	    internal Fixture _fixtureB;

        internal int _indexA;
        internal int _indexB;

	    internal Manifold _manifold = new Manifold();

	    internal int _toiCount;
    }
}
