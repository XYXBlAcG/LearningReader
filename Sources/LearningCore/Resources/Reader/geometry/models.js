(function (root, factory) {
  const models = factory();
  if (typeof module === 'object' && module.exports) module.exports = models;
  else root.SpaceGeometry = models;
})(typeof globalThis === 'object' ? globalThis : this, function () {
  'use strict';
  const dot = (a, b) => a.reduce((sum, value, index) => sum + value * b[index], 0);
  const add = (a, b) => a.map((value, index) => value + b[index]);
  const scale = (a, factor) => a.map(value => value * factor);
  const norm = a => Math.sqrt(dot(a, a));
  let sampleDensity=1;
  const sample = (low, high, count = 65) => {
    if(count>2)count=Math.max(3,2*Math.floor((count-1)*sampleDensity/2)+1);
    return Array.from({length: count}, (_, index) => low + (high - low) * index / (count - 1));
  };
  function withSampling(density,create) {
    const previous=sampleDensity;sampleDensity=density;
    try{return create();}finally{sampleDensity=previous;}
  }
  const diagonal = values => values.map((value, row) => values.map((_, column) => row === column ? value : 0));
  const quadrics = {
    ellipsoid: {name: '椭球面', equation: String.raw`\frac{x^2}{4}+\frac{y^2}{2.25}+\frac{z^2}{4}=1`, matrix: diagonal([1/4, 4/9, 1/4]), linear: [0,0,0], rhs: 1},
    single: {name: '单叶双曲面', equation: 'x² + y² − z² = 1', matrix: diagonal([1,1,-1]), linear: [0,0,0], rhs: 1},
    double: {name: '双叶双曲面', equation: 'z² − x² − y² = 1', matrix: diagonal([-1,-1,1]), linear: [0,0,0], rhs: 1},
    paraboloid: {name: '椭圆抛物面', equation: 'z = x² + y²', matrix: diagonal([1,1,0]), linear: [0,0,-1], rhs: 0},
    saddle: {name: '双曲抛物面', equation: 'z = x² − y²', matrix: diagonal([1,-1,0]), linear: [0,0,-1], rhs: 0},
    cylinder: {name: '斜柱面', equation: '(x − z)² + y² = 1', matrix: [[1,0,-1],[0,1,0],[-1,0,1]], linear: [0,0,0], rhs: 1},
    cone: {name: '圆锥面', equation: 'x² + y² = z²', matrix: diagonal([1,1,-1]), linear: [0,0,0], rhs: 0}
  };
  const residual = (model, point) => dot(point, model.matrix.map(row => dot(row, point))) + dot(model.linear, point) - model.rhs;

  function grid(first, second, point) {
    return first.map(u => second.map(v => point(u, v)));
  }

  function surfacePatches(model,range=3) {
    const angles = sample(0, 2 * Math.PI, 49);
    switch (model) {
      case quadrics.ellipsoid:
        return [grid(sample(0, Math.PI, 31), angles, (v,u) => [2*Math.sin(v)*Math.cos(u),1.5*Math.sin(v)*Math.sin(u),2*Math.cos(v)])];
      case quadrics.single:
        return [grid(sample(-Math.acosh(Math.max(1,range)), Math.acosh(Math.max(1,range)), 35), angles, (v,u) => [Math.cosh(v)*Math.cos(u),Math.cosh(v)*Math.sin(u),Math.sinh(v)])];
      case quadrics.double:
        return [1,-1].map(sign => grid(sample(0,Math.acosh(Math.max(1,range)),31),angles,(v,u) => [Math.sinh(v)*Math.cos(u),Math.sinh(v)*Math.sin(u),sign*Math.cosh(v)]));
      case quadrics.cylinder:
        return [grid(sample(-range,range,31),angles,(v,u) => [Math.cos(u)+v,Math.sin(u),v])];
      case quadrics.cone:
        return [1,-1].map(sign => grid(sample(0,range,31),angles,(v,u) => [v*Math.cos(u),v*Math.sin(u),sign*v]));
      case quadrics.paraboloid:
      case quadrics.saddle:
        return [grid(sample(-range,range,65),sample(-range,range,65),(x,y) => [x,y,x*x+(model===quadrics.saddle?-1:1)*y*y])];
      default: throw new Error('未知曲面');
    }
  }

  function section(model, axis, height,range=3) {
    const free = [0,1,2].filter(index => index !== axis);
    const [i,j] = free;
    const A = model.matrix[i][i], B = model.matrix[i][j], C = model.matrix[j][j];
    const d = 2*model.matrix[i][axis]*height+model.linear[i];
    const e = 2*model.matrix[j][axis]*height+model.linear[j];
    const rhs = model.rhs-model.matrix[axis][axis]*height*height-model.linear[axis]*height;
    const angle = Math.atan2(2*B,A-C)/2;
    const co = Math.cos(angle), si = Math.sin(angle);
    const snap = value => Math.abs(value)<1e-9 ? 0 : value;
    const eigen = [snap(A*co*co+2*B*co*si+C*si*si),snap(A*si*si-2*B*co*si+C*co*co)];
    const linear = [snap(d*co+e*si),snap(-d*si+e*co)];
    const center = eigen.map((value,index) => value ? -linear[index]/(2*value) : 0);
    const level = snap(rhs+dot(eigen,center.map(value => value*value)));
    const point = (u,v) => {
      const result = [0,0,0];
      result[axis] = height;
      result[i] = co*u-si*v;
      result[j] = si*u+co*v;
      return result;
    };
    const result = {kind:'空集',curves:[],free,coefficients:[A,B,C,d,e],rhs,axis,height};
    if (eigen[0] && eigen[1]) {
      if (eigen[0]*eigen[1]>0) {
        if (level/eigen[0]<0) return result;
        if (!level) {
          result.kind='一个点'; result.curves=[[point(...center)]];
        } else {
          result.kind=Math.abs(eigen[0]-eigen[1])<1e-9?'圆':'椭圆';
          result.curves=[sample(0,2*Math.PI,129).map(t => point(center[0]+Math.sqrt(level/eigen[0])*Math.cos(t),center[1]+Math.sqrt(level/eigen[1])*Math.sin(t)))];
        }
      } else if (!level) {
        result.kind='两条相交直线';
        result.curves=[1,-1].map(sign => sample(-range,range).map(t => point(center[0]+t,center[1]+sign*Math.sqrt(-eigen[0]/eigen[1])*t)));
      } else {
        result.kind='双曲线';
        const real = level/eigen[0]>0?0:1, other=1-real;
        const extent=Math.asinh(2*range/Math.sqrt(Math.abs(level/eigen[other])));
        result.curves=[1,-1].map(sign => sample(-extent,extent,129).map(t => {
          const q=[...center];
          q[real]+=sign*Math.sqrt(level/eigen[real])*Math.cosh(t);
          q[other]+=Math.sqrt(-level/eigen[other])*Math.sinh(t);
          return point(...q);
        }));
      }
    } else if (eigen[0] || eigen[1]) {
      const square = eigen[0]?0:1, other=1-square;
      if (linear[other]) {
        result.kind='抛物线';
        result.curves=[sample(-range,range,129).map(t => {
          const q=[0,0]; q[square]=t;
          q[other]=(rhs-eigen[square]*t*t-linear[square]*t)/linear[other];
          return point(...q);
        })];
      } else if (level/eigen[square]>=0) {
        const radius=Math.sqrt(level/eigen[square]);
        result.kind=radius?'两条平行直线':'一条直线';
        result.curves=(radius?[1,-1]:[1]).map(sign => sample(-range,range).map(t => {
          const q=[...center]; q[square]+=sign*radius; q[other]=t; return point(...q);
        }));
      }
    } else {
      const normSquared=d*d+e*e;
      if (normSquared) {
        result.kind='一条直线';
        result.curves=[sample(-range,range).map(t => point(d*rhs/normSquared-e*t,e*rhs/normSquared+d*t))];
      } else result.kind=rhs?'空集':'整个切割平面';
    }
    return result;
  }

  const project = (point, plane) => add(point,scale(plane.normal,(plane.constant-dot(point,plane.normal))/dot(plane.normal,plane.normal)));
  const projectDirection = (direction, plane) => add(direction,scale(plane.normal,-dot(direction,plane.normal)/dot(plane.normal,plane.normal)));
  function connector(t,s) {
    const first=[t,t,0],second=[1,s,1+s],vector=add(second,scale(first,-1));
    return {first,second,vector,distance:norm(vector),dot1:dot(vector,[1,1,0]),dot2:dot(vector,[0,1,1])};
  }
  return {quadrics,residual,surfacePatches,section,project,projectDirection,connector,dot,add,scale,norm,sample,withSampling};
});
